# Session D: goodput, burn-in and tenancy

!!! info "Status: planned"
    This page holds the plan and the acceptance test. I'll write the results from
    captured output after the session, as I did for Sessions A to C.

**Scope:** time slicing the L4 through the GPU Operator, with two tenant namespaces
under ResourceQuota. A PyTorch training job that checkpoints to object storage, gets
interrupted by an injected XID 79, and resumes, with the time it lost measured. A
3 hour burn-in with a stability record. And the acceptance runbook, filled in with
commands that ran on this cluster.

## Acceptance test

1. **Time slicing, from a commit.** One change to `gitops/values/gpu-operator.yaml`
   takes the node from `nvidia.com/gpu: 1` to `4`, through ArgoCD, with nobody on the
   node. Pods from both tenants run on the one L4 at the same time, and `nvidia-smi`
   shows their processes side by side.
2. **Quotas bite.** Each tenant namespace has a ResourceQuota of 2 GPUs. A third GPU
   pod in the same namespace is rejected by the API server, with the quota error
   captured.
3. **Goodput, measured.** A training job runs, checkpoints, is interrupted by an
   injected XID 79 (Session C's remediation drains it), waits for the gated return to
   service, and resumes from its last checkpoint to finish. Total time, useful compute
   time and lost time come out of step timestamps and Kubernetes event timestamps,
   and every input is published.
4. **Checkpoints outlive the node.** They're written to an S3-compatible store on the
   control plane, not to the GPU node's disk.
5. **Burn-in.** 3 hours of sustained tensor load, with a record of temperature,
   clocks, throttle reasons, ECC deltas and XID count, and a `dcgmi diag -r 3` before
   and after, timed. Labelled as a scaled-down version of a multi-day campaign.
6. **The runbook.** Every check in the [acceptance runbook](runbook.md) has a command,
   an expected result and a failure path, taken from what ran in Sessions A to D.

## Plan

Two billed sittings, so nothing depends on me staying at the keyboard for five hours.

| Part | What | Your time | GPU time |
|---|---|---|---|
| D1, authoring | Object store, tenants and quotas, the time slicing change (not merged), the training job and its goodput analysis with tests, burn-in and capture scripts. Deployed to the control plane where it can be, and checked there for free | 30 to 45 min | none |
| D2a, live | GPU up, pre-pull the PyTorch image, merge the time slicing commit, tenants and quotas, then the interrupted training run, GPU down | about 1.5 h | about 1.5 h |
| D2b, live | GPU up, `dcgmi diag -r 3`, 3 hour burn-in, `dcgmi diag -r 3` again, capture, GPU down | about 15 min, plus checking in | about 3.5 h |
| D3, write-up | This page and the runbook from the artifacts | about 30 min | none |

About 5 GPU hours in total, roughly EUR 4 at EUR 0.79/h.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Sharing mechanism | Time slicing, 4 replicas | The L4 can't do MIG, and MPS needs more setup for the same demonstration. The schema is `sharing.timeSlicing.resources[{name, replicas}]`, read from the device plugin at `v0.20.0` |
| How it's switched on | A commit to `devicePlugin.config` in the GPU Operator values, merged during D2a | Shows a GPU configuration change going through Git, not `kubectl` |
| Checkpoint storage | S3-compatible object store on the control plane | A replacement pod usually lands on another node, so checkpoints on the GPU node's disk would prove the wrong thing |
| Training workload | A small PyTorch model on synthetic data | Keeps the GPU busy without a dataset download on a billed node. The simulated page already says the workloads are synthetic |
| Goodput definition | Useful time is time spent on steps that made it into the final model. Lost time is the outage plus any steps redone after the last checkpoint | Written down before the run, so the number can't be shaped afterwards |
| Burn-in load | `dcgmproftester13` on the tensor cores, as in Session B | Known to hold the L4 at its power limit; Session B already has 20 minutes of it for comparison |

## Things I'll state up front

- **Time slicing has no isolation.** Tenants share the GPU's memory and fault domain.
  An XID from one tenant's process drains everyone on the node, and Session C's
  controller does exactly that. The write-up will show it rather than hide it.
- **The outage in the goodput run includes Session C's 5 minute lookback.** That's
  the price of a return to service node-problem-detector can't undo, and it belongs
  in the lost time.
- **One GPU node means the job can only resume on the node that failed.** On a fleet
  it would move to another node. The checkpoint store is the part that carries over.

## Open questions for D1

- Whether MinIO still publishes pinned community container images. I remember its
  distribution changing in 2025 and haven't checked. If it doesn't, I'll propose
  another S3-compatible store before building on it, not swap it in quietly.
- How the GPU Operator rolls out a `devicePlugin.config` change at `v26.7.0`: whether
  the device plugin restarts by itself, and what happens to running GPU pods when
  the node's `nvidia.com/gpu` count changes.
- How long `dcgmi diag -r 3` takes on an L4. Level 2 took 6 seconds in Session C.
- Pull time for the 4.3 GB `pytorch/pytorch:2.11.0-cuda12.8-cudnn9-runtime` image
  on the GPU node, which decides whether pre-pulling is enough.

## What happened

Not run yet.
