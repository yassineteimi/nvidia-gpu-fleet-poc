"""Run the controller: watch nodes, reconcile each change, and resync every node
whenever the watch ends, so nothing depends on a single event arriving.

One process, one node at a time. A fleet of thousands would want a work queue
and leader election; a PoC with one GPU node wants something readable.
"""

import logging
import os

from kubernetes import config, watch

from .controller import Remediator
from .kube import KubeCluster, to_node

log = logging.getLogger("gpu-remediator")


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    config.load_incluster_config()
    cluster = KubeCluster()
    remediator = Remediator(cluster, drain_timeout=int(os.environ.get("DRAIN_TIMEOUT_SECONDS", "300")))
    resync = int(os.environ.get("RESYNC_SECONDS", "30"))

    log.info("watching nodes for GPUUnhealthy=True, reason GPUXidFault")
    while True:
        for node in cluster.nodes():
            act(remediator, node)
        for event in watch.Watch().stream(cluster.core.list_node, timeout_seconds=resync):
            if event["type"] in ("ADDED", "MODIFIED"):
                act(remediator, to_node(event["object"]))


def act(remediator, node):
    try:
        outcome = remediator.reconcile(node)
    except Exception:
        log.exception("reconcile %s failed, will retry on the next resync", node.name)
        return
    if outcome != "healthy":
        log.info("%s: %s", node.name, outcome)


if __name__ == "__main__":
    main()
