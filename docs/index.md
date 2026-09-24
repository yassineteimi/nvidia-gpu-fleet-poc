# GPU fleet operations on upstream Kubernetes

**What this is.** A rented NVIDIA L4 node taken from a bare cloud instance to a
GitOps-managed, monitored, self-remediating GPU platform on upstream Kubernetes,
then torn down and rebuilt from Git. Everything here was run on real hardware and
the output on these pages is captured, not written from memory.

**What it is built to prove.** Sessions A and B are done and C and D are not, as the
build status below says. Driver and container toolkit lifecycle driven from Git rather
than from a shell. GPU health telemetry that surfaces the signals that actually
matter in Day 2 (XID, ECC, clock event reasons, not just utilisation). Automatic
cordon and drain when a GPU goes bad, with a gated path back to service. A measured
goodput figure across an interrupted training job. A cluster acceptance runbook.

**What is simulated.** The GPU hardware never failed. Session B injected an XID into
DCGM to exercise the alerting path, and Session C will inject one as a kernel log line
to exercise detection and remediation. One node stands in for a fleet. The burn-in is hours, not days.
Every simulation is listed on [What is simulated](simulated.md) with nothing omitted.

**How to reproduce it.** Clone the repo, set Scaleway credentials, run one script.
The GPU node is created, joined, driver-provisioned and running a CUDA workload
without a single manual step on the node.

```{ .sh .terminal }
$ git clone https://github.com/yassineteimi/nvidia-gpu-fleet-poc
$ cd nvidia-gpu-fleet-poc && cp .env.example .env    # fill in Scaleway keys
$ make cluster && make argocd                        # once
$ make up                                            # every session
```

---

## Build status

This repository is built in the open, one session at a time. Nothing below is
claimed until the session that produces it has actually run.

| Session | Scope | Status |
|---|---|---|
| A | Terraform nodes, kubeadm, ArgoCD, NFD, GPU Operator, CUDA acceptance | **Done.** Acceptance passed on a real L4, 2026-09-24 |
| B | DCGM telemetry, Grafana dashboard, XID and utilisation alerting | **Done.** All five criteria met on a real L4, one with a stated caveat, 2026-09-24 |
| C | node-problem-detector, remediation controller, fault injection | Not started |
| D | Time slicing and tenancy, goodput, burn-in, acceptance runbook | Not started |

## Stack

Upstream Kubernetes via kubeadm, no vendor distribution. Scaleway L4-1-24G GPU node
plus a small persistent control plane node, both provisioned by Terraform. ArgoCD in
app-of-apps from the first commit. NVIDIA GPU Operator with Node Feature Discovery
for the driver and toolkit. DCGM exporter, kube-prometheus-stack. Planned for Sessions C and D:
node-problem-detector with a custom GPU monitor. A remediation controller in Python
on the Kubernetes client. PyTorch with checkpointing as the acceptance workload.

## Honest scope

One GPU on one node is not a fleet. What transfers from this PoC is the method:
the driver is never touched by hand, the telemetry is the telemetry an operator
actually pages on, the remediation is a controller rather than a person, and the
acceptance procedure is written down with exit criteria. A real acceptance campaign
is multi-day, multi-rack, and includes NCCL bandwidth across nodes. This is a
scaled-down instance of the same method, and the pages say so wherever it matters.
