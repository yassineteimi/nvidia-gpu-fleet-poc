# What is simulated

The credibility of this PoC depends on this page being complete. If something here
was not produced by real hardware doing a real thing, it is listed below.

| Item | What is real | What is simulated | Why |
|---|---|---|---|
| GPU hardware fault | The detection path, the node condition, the cordon, the drain, the event trail and the return-to-service gate are all real and unmodified | The XID error itself. It is written into the kernel log by `scripts/inject-xid.sh` as an `NVRM: Xid` line | A rented L4 cannot be made to fail on demand, and deliberately damaging rented hardware is not an option |
| Fleet scale | Every operation performed is the same operation a fleet operator performs on one node | One node stands in for a fleet. There is no cross-node scheduling pressure and no correlated failure | Cost. One L4 at EUR 0.79/h fits a 5 hour weekly budget, a rack does not |
| Burn-in duration | The load, the telemetry, the thresholds and the stability record | The duration. Hours rather than days | See [Session D](04-goodput-and-burn-in.md). A real acceptance campaign is multi-day and multi-rack |
| Multi-tenancy | Two namespaces, real ResourceQuota enforcement, real time-sliced GPU sharing | The tenants are not real teams and the workloads are synthetic | Demonstrating the mechanism, not the organisation |
| Hardware handover | The acceptance runbook and its checks | There was no physical handover. The "handover" is a Terraform apply | No bare metal available at this budget |

## What is not simulated

Worth stating explicitly, because these are the parts most easily faked and were not:

- The NVIDIA driver and container toolkit are installed by the GPU Operator on a
  plain Ubuntu image. No preinstalled-driver image was used.
- Every component is deployed by ArgoCD from this repository. Nothing was installed
  by hand after the ArgoCD bootstrap.
- The utilisation-collapse alert in Session B fires on a genuinely killed job, not
  on an injected metric.
- The goodput figure is computed from real step timestamps and real Kubernetes event
  timestamps, both published in the repository.
