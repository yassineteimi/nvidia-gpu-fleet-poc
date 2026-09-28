# Artifacts

What's worth taking from this repository without reading the whole build.

| Artifact | What it is | Status |
|---|---|---|
| Captured cluster state | Raw `kubectl` and node output captured during each session, as text so you can read, search and diff it. The `session-a-*`, `session-b-*` and `session-c-*` files in [`docs/artifacts/`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/tree/main/docs/artifacts) | Sessions A, B and C |
| [Grafana dashboard](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/gitops/manifests/observability/dashboards/gpu-fleet.json) | The GPU fleet dashboard, 21 panels, loaded by the Grafana sidecar from Git rather than built in the UI | Done in Session B |
| [Prometheus alert rules](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/gitops/manifests/observability/gpu-alerts.yaml) | XID, ECC, row remapping, thermal and power throttling, utilisation collapse, exporter health. Each rule has a [`promtool` unit test](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/gitops/manifests/observability/tests/gpu-alerts.test.yaml) | Done in Session B |
| [Acceptance runbook](../runbook.md) | Cluster acceptance from handover to first production workload, with exit criteria and a failure path for every check | Skeleton; filled in during Session D |
| [Remediation controller](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/tree/main/controllers/gpu-remediator) | Python on the Kubernetes client: cordon, event, annotate, drain through the Eviction API, with unit tests. Plus the [node-problem-detector GPU rule](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/gitops/manifests/node-problem-detector/gpu-monitor.json) that feeds it | Done in Session C |
| Goodput method | How total, useful and lost time were measured, with the raw inputs | Session D |
