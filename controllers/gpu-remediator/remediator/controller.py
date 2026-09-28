"""What the controller does to a node, kept apart from how it talks to the API.

The Kubernetes calls live in kube.py behind the small interface used here, so
every decision below is unit tested against a fake cluster with no API server.

node-problem-detector sets GPUUnhealthy=True, reason GPUXidFault, when it sees a
fault XID in the kernel log. For such a node this controller:

  1. refuses, with an Event, if the node isn't a GPU node;
  2. cordons it and records the XID in annotations and an Event;
  3. drains it through the Eviction API, so PodDisruptionBudgets are honoured,
     leaving DaemonSet and mirror pods alone.

It never uncordons and never clears the condition. Getting back into service is
scripts/return-to-service.sh, gated on dcgmi diag, and a person runs it.
"""

import time
from dataclasses import dataclass, field
from datetime import datetime, timezone

from . import xid

CONDITION = "GPUUnhealthy"
FAULT_REASON = "GPUXidFault"
GPU_LABEL = "feature.node.kubernetes.io/pci-10de.present"

ANN = "gpu-fleet.io/"
ANN_XID = ANN + "xid"
ANN_XID_AT = ANN + "xid-logged-at"
ANN_CORDONED_AT = ANN + "cordoned-at"
ANN_DRAINED_AT = ANN + "drained-at"
ANN_REFUSED_AT = ANN + "refused-at"


@dataclass
class Condition:
    status: str
    reason: str = ""
    message: str = ""
    last_transition: str = ""


@dataclass
class Node:
    name: str
    uid: str = ""
    labels: dict = field(default_factory=dict)
    annotations: dict = field(default_factory=dict)
    unschedulable: bool = False
    conditions: dict = field(default_factory=dict)


@dataclass
class Pod:
    namespace: str
    name: str
    phase: str = "Running"
    owner_kinds: tuple = ()
    mirror: bool = False
    terminating: bool = False


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def evictable(pod):
    """kubectl drain's rules, minus the flags: DaemonSet pods would come straight
    back, mirror pods belong to the kubelet, and finished pods hold nothing."""
    if pod.phase in ("Succeeded", "Failed"):
        return False
    if pod.mirror or "DaemonSet" in pod.owner_kinds:
        return False
    return True


class Remediator:
    def __init__(self, cluster, drain_timeout=300, poll=2.0, clock=time.monotonic, sleep=time.sleep):
        self.cluster = cluster
        self.drain_timeout = drain_timeout
        self.poll = poll
        self.clock = clock
        self.sleep = sleep

    def reconcile(self, node):
        """Bring one node in line with its GPUUnhealthy condition. Returns a short
        word saying what it did, which the tests and the log both use."""
        if not self.unhealthy(node):
            return "healthy"
        # A watch event can carry a copy of the node older than this controller's
        # own last write. In Session C2, events queued during a drain arrived
        # without the drained-at annotation, and one drain was announced three
        # times. So a node that looks unhealthy is read again before anything
        # is done to it.
        node = self.cluster.node(node.name)
        if not self.unhealthy(node):
            return "healthy"
        cond = node.conditions[CONDITION]

        if node.labels.get(GPU_LABEL) != "true":
            if ANN_REFUSED_AT in node.annotations:
                return "refused"
            self.cluster.annotate(node.name, {ANN_REFUSED_AT: now_iso()})
            self.cluster.event(
                node, "Warning", "RemediationRefused",
                f"{CONDITION} is set but {node.name} has no {GPU_LABEL}=true label. "
                "Not cordoning a node that isn't a GPU node.")
            return "refused"

        parsed = xid.parse(cond.message)
        if parsed and not xid.is_fault(parsed[1]):
            # node-problem-detector's rule should never set the condition for an
            # application XID. If it does, its rule and this list disagree, and
            # draining a healthy GPU is the worse mistake.
            if ANN_REFUSED_AT not in node.annotations:
                self.cluster.annotate(node.name, {ANN_REFUSED_AT: now_iso()})
                self.cluster.event(
                    node, "Warning", "XidClassificationMismatch",
                    f"{CONDITION} names {xid.describe(parsed[1])}, which is an application "
                    "error, not a GPU fault. Check the node-problem-detector rule.")
            return "refused"

        if ANN_CORDONED_AT not in node.annotations:
            self.cordon(node, cond, parsed)
        if ANN_DRAINED_AT not in node.annotations:
            return self.drain(node)
        return "remediated"

    @staticmethod
    def unhealthy(node):
        cond = node.conditions.get(CONDITION)
        return cond is not None and cond.status == "True" and cond.reason == FAULT_REASON

    def cordon(self, node, cond, parsed):
        what = xid.describe(parsed[1]) if parsed else "an XID the controller could not parse"
        where = f" on PCI {parsed[0]}" if parsed else ""
        self.cluster.cordon(node.name, {
            ANN_XID: str(parsed[1]) if parsed else "unknown",
            ANN_XID_AT: cond.last_transition,
            ANN_CORDONED_AT: now_iso(),
        })
        node.annotations[ANN_CORDONED_AT] = "set"
        self.cluster.event(
            node, "Warning", "GPUFaultCordoned",
            f"{what}{where}. Cordoned; draining. Return to service with "
            f"make return-to-service NODE={node.name} after dcgmi diag passes.")

    def drain(self, node):
        deadline = self.clock() + self.drain_timeout
        while True:
            left = [p for p in self.cluster.pods_on(node.name) if evictable(p)]
            if not left:
                self.cluster.annotate(node.name, {ANN_DRAINED_AT: now_iso()})
                self.cluster.event(node, "Normal", "GPUNodeDrained",
                                   f"No workload pods left on {node.name}.")
                return "drained"
            if self.clock() >= deadline:
                self.cluster.event(
                    node, "Warning", "GPUNodeDrainStalled",
                    f"{len(left)} pod(s) still on {node.name} after {self.drain_timeout}s: "
                    + ", ".join(f"{p.namespace}/{p.name}" for p in left[:5]))
                return "drain-stalled"
            for pod in left:
                # A pod already on its way out has been evicted; asking again
                # adds nothing. A PodDisruptionBudget refusal is retried on the
                # next pass, the way kubectl drain does, never deleted past.
                if not pod.terminating:
                    self.cluster.evict(pod.namespace, pod.name)
            self.sleep(self.poll)
