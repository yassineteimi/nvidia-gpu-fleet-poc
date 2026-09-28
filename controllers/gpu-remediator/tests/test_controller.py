import copy

from remediator import controller as c
from remediator.controller import Condition, Node, Pod, Remediator

LINE_79 = ("NVRM: Xid (PCI:0000:01:00): 79, pid='<unknown>', name=<unknown>, "
           "GPU has fallen off the bus.")
LINE_13 = "NVRM: Xid (PCI:0000:01:00): 13, pid=4242, name=python3, Graphics Exception"


class FakeCluster:
    """Records every write; pods_on returns whatever the test put on the node,
    and an eviction removes the pod the way a real one eventually would."""

    def __init__(self, pods=(), blocked=()):
        self.pods = list(pods)
        self.blocked = set(blocked)
        self.calls = []
        self.stored = {}

    def given(self, node):
        """Put a node in the fake API server and return the copy a watch would carry."""
        self.stored[node.name] = copy.deepcopy(node)
        return node

    def node(self, name):
        return copy.deepcopy(self.stored[name])

    def annotate(self, name, annotations):
        self.calls.append(("annotate", name, sorted(annotations)))
        self.stored[name].annotations.update(annotations)

    def cordon(self, name, annotations):
        self.calls.append(("cordon", name, dict(annotations)))
        self.stored[name].annotations.update(annotations)
        self.stored[name].unschedulable = True

    def pods_on(self, name):
        return list(self.pods)

    def evict(self, namespace, name):
        self.calls.append(("evict", f"{namespace}/{name}"))
        if name in self.blocked:
            return False
        self.pods = [p for p in self.pods if p.name != name]
        return True

    def event(self, node, type_, reason, message):
        self.calls.append(("event", type_, reason, message))

    def kinds(self):
        return [call[0] for call in self.calls]

    def reasons(self):
        return [call[2] for call in self.calls if call[0] == "event"]


class FakeClock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t

    def sleep(self, seconds):
        self.t += seconds


def gpu_node(message=LINE_79, reason=c.FAULT_REASON, status="True", labels=None, **kw):
    return Node(
        name="gpu-fleet-gpu-01",
        labels={c.GPU_LABEL: "true"} if labels is None else labels,
        conditions={c.CONDITION: Condition(status, reason, message, "2026-09-30T10:00:00+00:00")},
        **kw,
    )


def remediator(cluster, timeout=60):
    clock = FakeClock()
    return Remediator(cluster, drain_timeout=timeout, poll=2, clock=clock, sleep=clock.sleep)


def test_healthy_node_is_left_alone():
    cluster = FakeCluster()
    node = gpu_node(status="False", reason="NoGPUXidFault", message="")
    assert remediator(cluster).reconcile(cluster.given(node)) == "healthy"
    assert cluster.calls == []


def test_node_without_the_condition_is_left_alone():
    cluster = FakeCluster()
    assert remediator(cluster).reconcile(cluster.given(Node(name="n"))) == "healthy"
    assert cluster.calls == []


def test_fault_xid_cordons_records_and_drains():
    workload = Pod("gpu-work", "trainer-0")
    daemon = Pod("gpu-operator", "nvidia-dcgm-x", owner_kinds=("DaemonSet",))
    cluster = FakeCluster(pods=[workload, daemon])

    assert remediator(cluster).reconcile(cluster.given(gpu_node())) == "drained"

    cordon = next(call for call in cluster.calls if call[0] == "cordon")
    assert cordon[2][c.ANN_XID] == "79"
    assert cordon[2][c.ANN_XID_AT] == "2026-09-30T10:00:00+00:00"
    assert ("evict", "gpu-work/trainer-0") in cluster.calls
    assert ("evict", "gpu-operator/nvidia-dcgm-x") not in cluster.calls
    assert cluster.reasons() == ["GPUFaultCordoned", "GPUNodeDrained"]
    message = [call[3] for call in cluster.calls if call[0] == "event"][0]
    assert "XID 79 (GPU has fallen off the bus) on PCI 0000:01:00" in message


def test_cordon_happens_before_any_eviction():
    cluster = FakeCluster(pods=[Pod("gpu-work", "trainer-0")])
    remediator(cluster).reconcile(cluster.given(gpu_node()))
    kinds = cluster.kinds()
    assert kinds.index("cordon") < kinds.index("evict")


def test_application_xid_never_cordons_even_if_the_condition_says_fault():
    cluster = FakeCluster(pods=[Pod("gpu-work", "trainer-0")])
    assert remediator(cluster).reconcile(cluster.given(gpu_node(message=LINE_13))) == "refused"
    assert "cordon" not in cluster.kinds()
    assert "evict" not in cluster.kinds()
    assert cluster.reasons() == ["XidClassificationMismatch"]


def test_non_gpu_node_is_refused_once_and_never_cordoned():
    cluster = FakeCluster(pods=[Pod("argocd", "server-0")])
    node = gpu_node(labels={})
    r = remediator(cluster)
    assert r.reconcile(cluster.given(node)) == "refused"
    assert cluster.reasons() == ["RemediationRefused"]
    node.annotations[c.ANN_REFUSED_AT] = "2026-09-30T10:00:01Z"
    assert r.reconcile(cluster.given(node)) == "refused"
    assert cluster.reasons() == ["RemediationRefused"]
    assert "cordon" not in cluster.kinds() and "evict" not in cluster.kinds()


def test_already_remediated_node_is_not_touched_again():
    cluster = FakeCluster(pods=[Pod("gpu-work", "trainer-0")])
    node = gpu_node(annotations={c.ANN_CORDONED_AT: "x", c.ANN_DRAINED_AT: "y"})
    assert remediator(cluster).reconcile(cluster.given(node)) == "remediated"
    assert cluster.calls == []


def test_interrupted_drain_resumes_without_cordoning_twice():
    cluster = FakeCluster(pods=[Pod("gpu-work", "trainer-0")])
    node = gpu_node(annotations={c.ANN_CORDONED_AT: "x"})
    assert remediator(cluster).reconcile(cluster.given(node)) == "drained"
    assert "cordon" not in cluster.kinds()


def test_unparseable_message_still_cordons():
    # The condition's reason is node-problem-detector saying "fault". If the line
    # changed format and the controller can't read the code, draining a node
    # that may be broken is safer than leaving work on it.
    cluster = FakeCluster()
    assert remediator(cluster).reconcile(cluster.given(gpu_node(message="NVRM: something new"))) == "drained"
    cordon = next(call for call in cluster.calls if call[0] == "cordon")
    assert cordon[2][c.ANN_XID] == "unknown"


def test_disruption_budget_is_retried_then_reported_not_forced():
    cluster = FakeCluster(pods=[Pod("gpu-work", "guarded-0")], blocked={"guarded-0"})
    assert remediator(cluster, timeout=10).reconcile(cluster.given(gpu_node())) == "drain-stalled"
    evictions = [call for call in cluster.kinds() if call == "evict"]
    assert len(evictions) == 5  # every 2 seconds for 10 seconds
    assert cluster.reasons() == ["GPUFaultCordoned", "GPUNodeDrainStalled"]


def test_terminating_and_finished_pods_are_not_evicted_again():
    done = Pod("gpu-work", "job-done", phase="Succeeded")
    leaving = Pod("gpu-work", "leaving", terminating=True)
    cluster = FakeCluster(pods=[done, leaving])
    remediator(cluster, timeout=4).reconcile(cluster.given(gpu_node()))
    assert ("evict", "gpu-work/leaving") not in cluster.calls
    assert ("evict", "gpu-work/job-done") not in cluster.calls


def test_mirror_pods_are_left_to_the_kubelet():
    assert not c.evictable(Pod("kube-system", "etcd-x", mirror=True))
    assert c.evictable(Pod("default", "web"))


def test_a_stale_watch_copy_does_not_drain_or_announce_twice():
    # Session C2: node events queued during a drain carried the node without
    # the drained-at annotation, and GPUNodeDrained was emitted three times.
    cluster = FakeCluster(pods=[Pod("gpu-work", "trainer-0")])
    stale = gpu_node()
    r = remediator(cluster)
    assert r.reconcile(cluster.given(stale)) == "drained"
    for _ in range(3):
        assert r.reconcile(copy.deepcopy(stale)) == "remediated"
    assert cluster.reasons() == ["GPUFaultCordoned", "GPUNodeDrained"]
    assert cluster.kinds().count("cordon") == 1


def test_a_node_that_recovered_since_the_watch_event_is_left_alone():
    cluster = FakeCluster(pods=[Pod("gpu-work", "trainer-0")])
    stale = gpu_node()
    cluster.given(gpu_node(status="False", reason="NoGPUXidFault", message=""))
    assert remediator(cluster).reconcile(stale) == "healthy"
    assert cluster.calls == []
