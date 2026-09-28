"""The Kubernetes API behind the controller's small interface.

Kept thin on purpose: every decision is in controller.py and tested there. What
lives here is translation between API objects and the controller's own types,
and the four writes the ClusterRole allows: patch a node, evict a pod, create an
Event, and nothing else.
"""

from kubernetes import client
from kubernetes.client.rest import ApiException

from .controller import Condition, Node, Pod, now_iso


def to_node(obj):
    conditions = {
        c.type: Condition(
            status=c.status,
            reason=c.reason or "",
            message=c.message or "",
            last_transition=c.last_transition_time.isoformat() if c.last_transition_time else "",
        )
        for c in (obj.status.conditions or [])
    }
    return Node(
        name=obj.metadata.name,
        uid=obj.metadata.uid or "",
        labels=dict(obj.metadata.labels or {}),
        annotations=dict(obj.metadata.annotations or {}),
        unschedulable=bool(obj.spec.unschedulable),
        conditions=conditions,
    )


def to_pod(obj):
    annotations = obj.metadata.annotations or {}
    return Pod(
        namespace=obj.metadata.namespace,
        name=obj.metadata.name,
        phase=obj.status.phase or "",
        owner_kinds=tuple(o.kind for o in (obj.metadata.owner_references or [])),
        mirror="kubernetes.io/config.mirror" in annotations,
        terminating=obj.metadata.deletion_timestamp is not None,
    )


class KubeCluster:
    def __init__(self, core=None, component="gpu-remediator"):
        self.core = core or client.CoreV1Api()
        self.component = component

    def nodes(self):
        return [to_node(n) for n in self.core.list_node().items]

    def node(self, name):
        return to_node(self.core.read_node(name))

    def annotate(self, name, annotations):
        self.core.patch_node(name, {"metadata": {"annotations": annotations}})

    def cordon(self, name, annotations):
        # One patch, so a node is never cordoned without saying why.
        self.core.patch_node(name, {"spec": {"unschedulable": True},
                                    "metadata": {"annotations": annotations}})

    def pods_on(self, name):
        pods = self.core.list_pod_for_all_namespaces(field_selector=f"spec.nodeName={name}")
        return [to_pod(p) for p in pods.items]

    def evict(self, namespace, name):
        body = client.V1Eviction(metadata=client.V1ObjectMeta(name=name, namespace=namespace))
        try:
            self.core.create_namespaced_pod_eviction(name, namespace, body)
            return True
        except ApiException as e:
            if e.status == 404:  # already gone
                return True
            if e.status == 429:  # a PodDisruptionBudget said not now
                return False
            raise

    def event(self, node, type_, reason, message):
        # Node events live in the default namespace, which is where
        # kubectl describe node looks for them.
        stamp = now_iso()
        self.core.create_namespaced_event("default", client.CoreV1Event(
            metadata=client.V1ObjectMeta(generate_name=f"{node.name}.gpu-remediator."),
            involved_object=client.V1ObjectReference(kind="Node", name=node.name, uid=node.uid),
            type=type_,
            reason=reason,
            message=message,
            source=client.V1EventSource(component=self.component),
            first_timestamp=stamp,
            last_timestamp=stamp,
            count=1,
        ))
