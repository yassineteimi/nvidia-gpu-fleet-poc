# GPU fleet operations on upstream Kubernetes

A GPU cloud sells GPUs, but what customers really pay for is GPUs that stay up through
a training run. This project shows the operations behind that, on one NVIDIA L4 I
rented by the hour: a driver installed from Git, health telemetry worth paging on, a
broken GPU pulled out of service automatically, and the cost of a failure measured to
the second.

New to GPU infrastructure? Start with [the use cases](use-cases.md), which explain
each piece without assuming you run clusters.

## Results

| Use case | What happened on the L4 |
|---|---|
| [Bring GPUs online the same way every time](01-platform.md) | The GPU Operator installed driver `595.91.07`, pinned in Git, on a node that booted with no driver |
| [See a failing GPU before the customer does](02-observability.md) | A simulated XID 79 reached Alertmanager as a critical alert in 32 s, and a real power-throttling alert fired under load |
| [Take a broken GPU out of service on its own](03-fault-remediation.md) | An injected XID 79 cordoned the node in 0.12 s and drained it in 2.5 s |
| [Share one GPU between teams](04-goodput-and-burn-in.md#from-a-commit-to-four-gpus) | One commit turned the L4 into 4 slices in 88 s, and a team's quota refused its third pod |
| [Measure a training run's goodput](04-goodput-and-burn-in.md#where-the-1383-seconds-went) | A job lost its GPU and resumed from a checkpoint: 66.4% of its time was useful, and most of the loss was one 5 minute rule |
| [Accept new hardware](04-goodput-and-burn-in.md#the-burn-in) | 3 hours at full load, 65 °C flat, no throttling and no errors; diagnostics passed before and after |

All four sessions ran between 24 September and 3 October 2026. The cluster is
destroyed now, so nothing here is a live system: every result links to output
committed during a session.

## Worth reading

- [Findings](findings.md): what didn't match the documentation or my assumptions,
  such as a Prometheus function that misses the first GPU error on a node.
- [What is simulated](simulated.md): the full list. A PoC is only as credible as what
  it admits.
- [The runbook](runbook.md): how I'd accept a GPU node, step by step, with the output
  from this cluster behind each check.

## Scope

One GPU on one node isn't a fleet, and I don't pretend otherwise. The method is what
carries over: nobody installs the driver by hand, the alerts are the ones an operator
pages on, a controller does the remediation, and acceptance has written exit criteria.
A real acceptance campaign runs for days across racks and measures bandwidth between
nodes; this ran for hours on one node, and each page says where that matters.

```{ .sh .terminal }
$ git clone https://github.com/yassineteimi/nvidia-gpu-fleet-poc
$ cd nvidia-gpu-fleet-poc && cp .env.example .env    # fill in Scaleway keys
$ make cluster && make argocd                        # once
$ make up                                            # every session
```
