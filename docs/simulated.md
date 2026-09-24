# What is simulated

If something in this project didn't come from real hardware doing a real thing, it's
on this page. Rows for Sessions C and D describe the plan, because those sessions
haven't run yet.

| Item | Real | Simulated | Why |
|---|---|---|---|
| XID seen by DCGM (Session B, done) | The DCGM exporter, the counter it derives, the Prometheus rule, and Alertmanager receiving a critical alert | The XID. `scripts/inject-xid-dcgm.sh` wrote the value 79 into DCGM's field cache with `dcgmi test --inject`. Nothing happened on the GPU or in the kernel log | It tests the path from DCGM to an alert without a real fault. Session C injects into the kernel log instead, because that's what its detection reads |
| GPU hardware fault (Session C, planned) | Detection, the node condition, cordon, drain, the event trail and the gate back into service | The XID. `scripts/inject-xid.sh` will write an `NVRM: Xid` line into the kernel log | I can't make a rented L4 fail on demand, and damaging rented hardware on purpose isn't an option |
| Fleet scale | Every operation is the one a fleet operator runs, on one node | One node stands in for a fleet: no cross-node scheduling pressure, no correlated failures | Cost. One L4 at EUR 0.79/h fits a 5 hour weekly budget; a rack doesn't |
| Burn-in duration (Session D, planned) | The load, the telemetry, the thresholds and the stability record | The duration: hours, not days | A real acceptance campaign runs for days across racks. See [Session D](04-goodput-and-burn-in.md) |
| Multi-tenancy (Session D, planned) | Two namespaces, real ResourceQuota enforcement, real time-sliced GPU sharing | The tenants aren't real teams and the workloads are synthetic | It shows the mechanism, not the organisation |
| Hardware handover | The acceptance runbook and its checks | There's no physical handover. The "handover" is a Terraform apply | No bare metal at this budget |

## What isn't simulated

These are the parts that would be easiest to fake:

- **The driver install.** The GPU Operator installs the NVIDIA driver and container
  toolkit on an image that has no driver. Scaleway doesn't offer plain Ubuntu on GPU
  instances, so I use `kapsule_noble`, the image Scaleway's own managed Kubernetes
  boots before its GPU Operator installs the driver. The node checks for a driver on
  first boot and stops if it finds one.
- **Deployment.** ArgoCD deploys every component from this repository. After the
  ArgoCD bootstrap, nothing was installed by hand.
- **The utilisation-collapse alert** (Session B) fired on a real tensor load on the L4
  going idle, not on an injected metric. One caveat, explained in
  [Session B](02-observability.md#the-load-job-i-didnt-actually-kill): the load had
  finished its 20 minutes a few seconds before I killed it, so the alert saw a job end
  rather than a job killed.
- **The power-throttling alert** (Session B) fired on real power capping under that
  load. I didn't arrange it.
- **The goodput figure** (Session D, planned) will come from real step timestamps and
  real Kubernetes event timestamps, both published in the repository.
