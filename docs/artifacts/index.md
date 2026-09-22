# Artifacts

The things worth taking away from this repository without reading the whole build.

| Artifact | What it is | Status |
|---|---|---|
| [Acceptance runbook](../runbook.md) | Cluster acceptance from handover to first production workload, with exit criteria and a failure path for every check | Session D |
| Grafana dashboard JSON | GPU fleet dashboard, sidecar-managed, not clicked into the UI | Session B |
| Prometheus alert rules | XID, ECC, thermal throttle, utilisation collapse, exporter down | Session B |
| Remediation controller | Python on the Kubernetes client: cordon, event, annotate, drain | Session C |
| Goodput method | How total, useful and lost time were measured, with the raw inputs | Session D |
