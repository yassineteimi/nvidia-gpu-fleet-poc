# Session C: fault detection and remediation

!!! info "Status: C1 written and tested offline, not yet deployed"
    The detector rule, the controller and the scripts exist and pass their tests.
    Nothing has run on the cluster yet, and nothing has run on a GPU.

**Scope:** node-problem-detector reads the kernel log for `NVRM: Xid` and sets a
`GPUUnhealthy` node condition. A Python controller reacts: cordon, emit an event,
annotate, drain. Returning a node to service is a separate, gated command. The fault
itself is injected and labelled as simulated.

```text
echo "NVRM: Xid (PCI:0000:01:00): 79, ..." > /dev/kmsg        (simulated)
  -> node-problem-detector, GPU kernel log rule: a GPUXid Event for every XID,
     and GPUUnhealthy=True (reason GPUXidFault) for fault XIDs only
  -> gpu-remediator: cordon, Event with the decoded XID, annotations, drain via the Eviction API
  -> make return-to-service NODE=...: dcgmi diag must pass, then clear the condition, then uncordon
```

## Acceptance test

1. One command injects XID 79 on the GPU node while a GPU workload runs on it. Within
   60 seconds the node has `GPUUnhealthy=True` and is `SchedulingDisabled`, and the
   controller's Event names the decoded XID.
2. The workload is evicted and nothing but DaemonSet pods is left on the node. The
   time from injection to the end of the drain is measured and published, whatever it
   turns out to be.
3. XID 13 (an application error) produces an Event and **no** cordon.
4. The same injection on the control plane sets the condition, and the controller
   refuses to touch the node, because it isn't a GPU node.
5. `make return-to-service` refuses to uncordon while `dcgmi diag` fails or while the
   condition is still set, and on success the workload gets scheduled on the node
   again.
6. The controller has unit tests that run offline in CI, like the alert rules.

## Plan

| Part | What | GPU cost |
|---|---|---|
| C1, authoring | node-problem-detector Application with the GPU monitor, the controller and its tests, the CI image build, the inject, return-to-service and capture scripts. Deployed to the control plane, and criterion 4 tested there | none |
| C2, live | GPU up, workload running, XID 79 then XID 13 injected, timings captured, diag and return to service, GPU down | about an hour |
| C3, write-up | This page from the artifacts, and the simulated page updated | none |

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Which XIDs cordon | Any XID except 13, 31, 43, 45, 68 and 109 | The device plugin's list in `internal/rm/health.go` at v0.20.0, the same one the Session B alerts use. Prometheus, the scheduler and the controller shouldn't disagree about whether a GPU is broken |
| Where that decision lives | In the node-problem-detector rule, with the controller checking it again | My first plan put it in the controller. Reading node-problem-detector changed that: see below. Go's regex engine has no lookahead, so the rule spells out "any number except these six", and a test checks every code from 0 to 2000 |
| Controller packaging | Image built by GitHub Actions for `linux/amd64`, pushed to ghcr.io, pinned by digest in Git | Looks like production, has no local build step, and avoids the Apple Silicon `exec format error` trap |
| Diag level for return to service | `dcgmi diag -r 2`, configurable | A few minutes on a billed GPU. A real fleet would use level 3 or 4, and the runbook will say so |
| node-problem-detector deployment | The upstream kustomization at tag `v1.36.0`, with the image overridden | There's no upstream Helm chart. The manifest at that tag still references image `v0.8.19`, so I set the image to the release I actually read |
| What the injection proves | The kernel log path only | The device plugin and DCGM learn about XIDs from NVML, not from the kernel log, so they won't see an injected line. The GPU will keep advertising itself as healthy, and I'll show that rather than hide it |

## What reading the source changed

**Clearing the condition needs a restart, and the restart needs a wait.** I read the
kernel log watcher and condition manager in node-problem-detector `v1.36.0` before
designing return to service:

- A "permanent" condition stays set for the life of the process. The condition
  manager also re-sends its own view of every condition at least every 5 minutes
  (`--k8s-exporter-heartbeat-period`), so if I patched the node's condition back to
  False by hand, node-problem-detector would set it to True again.
- On startup, conditions go back to their defaults, but the kernel log watcher
  replays every line newer than the monitor's `lookback`. The stock kernel monitor
  uses 5 minutes. Restart it within 5 minutes of the XID and the node trips again.

So return to service works like this: refuse until `lookback` has passed since the
last XID, run `dcgmi diag`, restart the node-problem-detector pod on that node, check
that the condition is back to False, and only then uncordon. I'll keep the 5 minute
`lookback` for the GPU monitor, because it's also what stops a real XID from being
lost when node-problem-detector restarts. A level 2 diag takes a few minutes anyway,
so the wait costs little.

**One condition can't carry every XID.** Once a permanent condition is True with a
given reason, node-problem-detector doesn't update its message again. If every XID
fed one condition and the controller classified them, an XID 13 followed by an XID 79
would leave the condition saying 13, and the node would never be drained. So the rule
itself only sets `GPUUnhealthy` for fault XIDs, and a separate temporary rule emits a
`GPUXid` Event for every XID, application errors included. The controller still
checks the code, and refuses to drain if the condition ever names an application
error.

**The kernel log line gets trimmed.** node-problem-detector passes each kmsg line
through `strings.TrimSpace`. When the driver has no message to add, its line ends in
`79, `, which arrives as `79,`. A rule ending in `, .*` would miss it; the rule ends in
`,.*`, and a test covers the bare line.

## C1: what I wrote, and how I checked it

| Piece | Where | How I checked it |
|---|---|---|
| The Xid line format | Read from `src/nvidia/src/kernel/gpu/rc/kernel_rc.c` at driver tag `595.91.07` | Three shapes: with a process, without one, and with MIG attribution inside the parenthesis. Every test uses them |
| GPU monitor for node-problem-detector | `gitops/manifests/node-problem-detector/gpu-monitor.json` | Run through node-problem-detector's own `systemlogmonitor` package at `v1.36.0` (`make test-npd-rules`): every XID from 0 to 2000 classified like the device plugin, all three line shapes matched, non-Xid lines ignored, a fault after an application error still caught. Four deliberate breaks of the rule each failed a test |
| node-problem-detector deployment | `gitops/manifests/node-problem-detector/`, `gitops/apps/node-problem-detector.yaml`, wave 3 | `kustomize build` renders the upstream base with the image at `v1.36.0`, the GPU monitor in the ConfigMap and the volume, and the flags running it |
| `gpu-remediator` | `controllers/gpu-remediator/` | 40 `pytest` tests against a fake cluster (`make test-controller`): cordon before any eviction, DaemonSet, mirror and finished pods left alone, disruption budgets retried and never forced, non-GPU nodes refused, application XIDs never drained, no second cordon. Three deliberate breaks each failed a test |
| Controller RBAC | `gitops/manifests/gpu-remediator/rbac.yaml` | Exactly the calls in `kube.py`. No pod delete, so it can't bypass a disruption budget, and no write to `nodes/status`, so it can't clear the condition |
| Controller image | `.github/workflows/remediator-image.yml` | Not built yet: no Docker daemon where I wrote this. CI builds it for `linux/amd64` after the tests pass, and prints the digest to pin |
| Scripts | `inject-xid.sh`, `return-to-service.sh`, `gpu-workload.sh`, `capture-c.sh` | `shellcheck`. The injected line has the driver's exact shape, and its message says SIMULATED, so the node's own kernel log says where it came from |

## Still open

- Whether `registry.k8s.io/node-problem-detector/node-problem-detector:v1.36.0` exists.
  The registry isn't reachable from where I wrote this, and upstream promotes release
  images by hand, so a git tag doesn't guarantee one. The first sync answers it.
- How long `dcgmi diag -r 2` takes on an L4 running against the standalone host engine.
- Whether 60 seconds holds. The cordon should take seconds; the drain waits for each
  pod's grace period, which is why criterion 2 is a measured time, not a limit.

## What happened

Not run yet.
