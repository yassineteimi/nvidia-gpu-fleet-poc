# Session D: goodput, burn-in and tenancy

!!! info "Status: D1 done, no GPU time yet"
    The object store and the tenants are in Git for ArgoCD to deploy on the control
    plane. The trainer, the
    goodput analysis and the time slicing config are tested without a GPU, and
    the D2 scripts are written. Nothing below has touched the L4. I'll write the
    results from captured output after the GPU sittings, as I did for Sessions A to C.

**Scope:** time slicing the L4 through the GPU Operator, with two tenant namespaces
under ResourceQuota. A PyTorch training job that checkpoints to object storage, gets
interrupted by an injected XID 79, and resumes, with the time it lost measured. A
3 hour burn-in with a stability record. And the acceptance runbook, filled in with
commands that ran on this cluster.

## Acceptance test

1. **Time slicing, from a commit.** One line in `gitops/apps/gpu-operator.yaml`, adding
   `gitops/values/gpu-operator-time-slicing.yaml` to its value files, takes the node
   from `nvidia.com/gpu: 1` to `4`, through ArgoCD, with nobody on the node. Pods from both tenants run on the one L4 at the same time, and `nvidia-smi`
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
| D1, authoring | Object store, tenants and quotas, the time slicing change (not merged), the training job and its goodput analysis with tests, burn-in and capture scripts. Deployed to the control plane where it can be, and checked there for free | 30 to 45 min, done | none |
| D2a, live | GPU up, pre-pull the PyTorch image, merge the time slicing commit, tenants and quotas, then the interrupted training run, GPU down | about 1.5 h | about 1.5 h |
| D2b, live | GPU up, `dcgmi diag -r 3`, 3 hour burn-in, `dcgmi diag -r 3` again, capture, GPU down | about 15 min, plus checking in | about 3.5 h |
| D3, write-up | This page and the runbook from the artifacts | about 30 min | none |

About 5 GPU hours in total, roughly EUR 4 at EUR 0.79/h.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Sharing mechanism | Time slicing, 4 replicas | The L4 can't do MIG, and MPS needs more setup for the same demonstration. The schema is `sharing.timeSlicing.resources[{name, replicas}]`, read from the device plugin at `v0.20.0` |
| How it's switched on | A commit to `devicePlugin.config` in the GPU Operator values, merged during D2a | Shows a GPU configuration change going through Git, not `kubectl` |
| Checkpoint storage | Garage v2.4.1, one node, on the control plane | A replacement pod usually lands on another node, so checkpoints on the GPU node's disk would prove the wrong thing. I'd planned on MinIO, but its GitHub repository now says it's no longer maintained and the community edition ships as source only. Garage publishes a pinned image and runs as one node with a default bucket and key from environment variables |
| Garage's secrets | Generated in the cluster by a bootstrap Job, never in Git | The Job creates the RPC secret and the S3 key once, keeps them on every later sync, and copies the key into a `checkpoint-s3` Secret in each tenant namespace. I didn't use Garage's Helm chart: it makes its RPC secret with `lookup`, which returns nothing under ArgoCD's `helm template`, so the secret would change on every sync |
| How a time slicing change rolls out | The config is named after its content (`ts-4`) | The device plugin's config-manager at v0.20.0 reacts to the node label `nvidia.com/device-plugin.config`, never to the ConfigMap's content. Editing `replicas` under the same name would leave the running plugin on the old value. A new name changes the ClusterPolicy, and the operator rolls the plugin |
| Surviving the interruption | `podFailurePolicy` ignores the `DisruptionTarget` condition; `backoffLimit: 0` | An eviction through the Eviction API, which is how gpu-remediator drains, isn't counted as a failure, so the Job makes a replacement pod. Any other failure ends the run, so a crash can't hide in the goodput figure as a quiet retry |
| The step log | Each attempt writes its own log to the bucket, flushed every 5 s and on the way out | The evicted pod is deleted, and its container log with it. The analysis can't depend on a pod that no longer exists |
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

## What D1 built, and how I checked it without a GPU

| Piece | Where | Checked by |
|---|---|---|
| Tenants and quotas | `gitops/manifests/tenants/`, wave 4 | `tenant-a` and `tenant-b`, each with a ResourceQuota of `requests.nvidia.com/gpu: 2`. Schema-checked with kubeconform; the refusal itself needs the GPU node |
| Checkpoint store | `gitops/manifests/checkpoint-store/`, wave 5 | The Garage v2.4.1 binary, run locally with this exact `garage.toml`: a 40 MB multipart upload and download, and a restart that kept the bucket and key |
| Time slicing config | `gitops/values/gpu-operator-time-slicing.yaml`, not yet listed in the Application | Parsed by the device plugin's own config loader at v0.20.0 (`make test-time-slicing`). A misspelt key and `replicas: 1` both fail, as they should |
| Training loop and store | `workloads/goodput/trainer/` | 8 unit tests, plus an end to end test against a real Garage server: interrupted at step 130, resumed from the checkpoint at 100, 30 steps redone, only the two newest checkpoints kept. CI runs it against the pinned Garage image |
| Goodput analysis | `workloads/goodput/trainer/goodput.py` | Unit tests on hand-made step logs with known answers |
| Trainer image | `workloads/goodput/Dockerfile`, built by CI, pinned by digest in `job.yaml` | The build runs the PyTorch backend on CPU for two steps and a checkpoint round trip, and publishes nothing if that fails. It has never run on a GPU: bf16 autocast and the step time are for D2a to show |
| D2 scripts | `scripts/tenancy.sh`, `goodput.sh`, `burn-in.sh` | shellcheck, and every manifest they generate rendered and schema-checked |

The end to end test found a real bug before any GPU time. An evicted attempt's step
log was only flushed every 5 seconds, so the last few steps before the kill vanished
and would have been counted as outage, not redone work. The test expected 30 redone
steps and got 28. The loop now flushes the log on any exit, and SIGTERM is turned into
a clean exit so that the flush runs.

## The D2 steps

D2a, about 1.5 hours of GPU time:

1. `make up`, then `make prepull` (times the pull of the 4 GB image onto the node).
2. Push the one-line time slicing commit, then `make tenancy-wait` (times how long
   until the node advertises 4 GPUs).
3. `make tenancy`, `make tenancy-capture`, `make tenancy-stop`.
4. `make goodput`. After step 400, `SESSION=d make inject-xid NODE=gpu-fleet-gpu-01 XID=79`.
5. After the 5 minute lookback, `SESSION=d make return-to-service NODE=gpu-fleet-gpu-01`.
6. When the Job completes, `make goodput-capture`, then `make down`.

D2b, about 3.5 hours of GPU time:

1. `make up`, `make burn-in-diag LABEL=before`, `make burn-in`.
2. Three hours later, `make burn-in-capture`, `make burn-in-diag LABEL=after`, `make down`.

## Still open

- What happens to a running GPU pod when the device plugin restarts with the new
  config. I start the tenants after the switch, so it doesn't matter for the
  results, but I'd like to know.
- How long `dcgmi diag -r 3` takes on an L4. Level 2 took 6 seconds in Session C.
- How long the 4.3 GB PyTorch image takes to pull on the GPU node.
- How fast a training step really is. My estimate is about 0.2 seconds (13 TFLOP a
  step in bf16), which puts 3000 steps at about 10 minutes and a checkpoint every
  40 seconds. The first run will tell.

## What happened

Not run yet.
