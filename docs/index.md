# GPU fleet operations on upstream Kubernetes

I take a rented NVIDIA L4 from a bare cloud instance to a GPU node that ArgoCD
manages, Prometheus monitors and, from Session C on, a controller remediates. Then I
destroy it and rebuild it from Git. All of it ran on real hardware. The terminal
output on these pages was captured during the sessions and links back to files in
`docs/artifacts/`.

## What I'm building towards

- Driver and container toolkit lifecycle driven from Git, not from a shell on the node.
- GPU telemetry an operator would actually page on: XID, ECC, row remapping and clock
  event reasons, not only utilisation.
- Automatic cordon and drain when a GPU goes bad, and a gated way back into service.
- A measured goodput figure for a training job that gets interrupted, plus an
  acceptance runbook with exit criteria.

Sessions A and B are done. C and D aren't, and the table below is the only place I
claim progress.

## Build status

| Session | Scope | Status |
|---|---|---|
| A | Terraform nodes, kubeadm, ArgoCD, NFD, GPU Operator, CUDA acceptance | **Done.** Acceptance passed on a real L4, 2026-09-24 |
| B | DCGM telemetry, Grafana dashboard, XID and utilisation alerting | **Done.** All five criteria met on a real L4, one with a caveat, 2026-09-24 |
| C | node-problem-detector, remediation controller, fault injection | Not started |
| D | Time slicing and tenancy, goodput, burn-in, acceptance runbook | Not started |

## Worth reading first

- [Session B](02-observability.md): a real power-throttling alert on the L4, a
  simulated XID 79 traced from DCGM to Alertmanager in 32 seconds, and a load job
  that didn't quite get killed.
- [Findings](findings.md): what didn't match the documentation or my assumptions.
  Two examples: `increase()` misses the first XID on a node, and it also over-counts
  pod restarts.
- [What is simulated](simulated.md): the full list, because a PoC is only as credible
  as what it admits.

## Reproducing it

Clone the repo, add Scaleway credentials, and `make up` does the rest: it creates the
GPU node, joins it, lets the GPU Operator install the driver and runs a CUDA workload,
without anyone logging into the node.

```{ .sh .terminal }
$ git clone https://github.com/yassineteimi/nvidia-gpu-fleet-poc
$ cd nvidia-gpu-fleet-poc && cp .env.example .env    # fill in Scaleway keys
$ make cluster && make argocd                        # once
$ make up                                            # every session
```

## Stack

Upstream Kubernetes through kubeadm, no vendor distribution. A Scaleway L4-1-24G GPU
node and a small control plane that stays up between sessions, both created by
Terraform. ArgoCD app-of-apps from the first commit, the NVIDIA GPU Operator with Node
Feature Discovery, the DCGM exporter and kube-prometheus-stack. Sessions C and D add
node-problem-detector with a GPU monitor, a remediation controller in Python on the
Kubernetes client, and a PyTorch training job with checkpointing.

## Scope

One GPU on one node isn't a fleet, and I don't pretend otherwise. The method is what
carries over: nobody installs the driver by hand, the alerts are the ones an operator
pages on, a controller does the remediation, and acceptance has written exit criteria.
A real acceptance campaign runs for days across racks and measures NCCL bandwidth
between nodes; this runs for hours on one node, and each page says where that matters.
