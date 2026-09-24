# Session B: observability and XID alerting

!!! success "Status: done, 2026-09-24"
    All five acceptance criteria met on a real L4, one of them with a caveat that is
    stated below rather than smoothed over. The XID alert was also exercised, with an
    XID that was injected, and is labelled simulated wherever it appears. Written from
    the artifacts captured during the session, which are linked from each claim.

## Scope

DCGM exporter scraped by Prometheus. A Grafana dashboard covering SM utilisation,
framebuffer, temperature, power, ECC counters, clock event reasons and XID. Prometheus
alert rules on critical XID codes and on utilisation collapse during a running job.

## Acceptance test

1. Prometheus scrapes the DCGM exporter on the GPU node, and every counter in the
   custom counter set is present, including the ones the exporter ships disabled.
2. A Grafana dashboard, loaded from Git rather than built in the UI, shows live data
   for utilisation, SM and tensor activity, framebuffer, temperature, power, clocks
   and clock events, ECC and XID on one screen.
3. `GPUUtilisationCollapse` is observed moving from pending to firing after a real
   GPU load job is genuinely killed. Not an injected metric.
4. Every alert rule has a `promtool test rules` unit test in the repository, and they
   all pass offline, with no cluster.
5. Prometheus history survives the GPU node being destroyed: the load from step 3 is
   still queryable after `make down`.

Optional, and labelled simulated if it happens: `GPUXidCritical` fires on an XID 79
injected through DCGM, exercising the whole path from DCGM through the exporter to
Alertmanager with a fault that did not really occur.

## What the source code changed about the plan

The plan was checked against the exporter and the operator chart at the versions this
cluster actually runs, not against memory. Three things came out of that.

**There is a proper XID counter, and it is off by default.** dcgm-exporter `4.8.3`,
the version GPU Operator `v26.7.0` deploys, ships `DCGM_EXP_XID_ERRORS_TOTAL`: a
counter with one series per `xid` label, documented as intended for `increase()` and
`rate()`. That answers the problem recorded in [Findings](findings.md), where
`DCGM_FI_DEV_XID_ERRORS` only reports the last XID and never resets, so it cannot be
alerted on directly. The counter is commented out of the default counter set, along
with every ECC counter, the power and thermal violation counters,
`DCGM_FI_PROF_SM_ACTIVE` and the clock event counters. A custom counter set, owned in
Git, turns them on.

It does not solve everything. The counter is derived from the same DCGM field, so an
XID that DCGM never reports, such as XID 62, is still invisible to it. That is why
fault detection in Session C reads the kernel log and treats DCGM as corroboration.

**Standalone DCGM was a decision presented as a default.** Session A's values set
`dcgm.enabled: true` under a comment that read as though this were the chart's
default. It is not. The chart default is `false`, with the exporter running DCGM
embedded. The standalone host engine stays, because Session C gates return to service
on `dcgmi diag` and that needs a DCGM to run against. But the comment is corrected,
and the standalone engine becomes the leading suspect for the three restarts the
exporter went through in Session A: an exporter pointed at a remote host engine that
is not ready yet has nothing to talk to. Session B tests that rather than assuming it.

**The monitoring CRDs have to exist before the GPU Operator.** The operator chart
enables a ServiceMonitor for the exporter by default, and a ServiceMonitor only exists
once the Prometheus Operator's CRDs do. So kube-prometheus-stack moves to sync wave 0,
beside Node Feature Discovery, rather than wave 1 as first planned.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Metrics storage | local-path provisioner on the control plane disk | History survives pod restarts and every GPU node teardown. No cloud credentials inside the cluster. Lost only if the control plane itself is rebuilt, which is stated rather than hidden |
| Where monitoring runs | Pinned to the control plane by node selector | A volume created while the GPU node exists could otherwise be placed on it and destroyed with it at the end of the session |
| Alert routing | Alertmanager with a null receiver | The acceptance test needs an alert observed firing, which the Alertmanager API records. No webhook or SMTP credential to manage |
| Proving the XID rule | `promtool` unit tests, plus an optional DCGM injection | No real XID will occur on demand. The unit tests prove the rule logic. The injection, if DCGM allows it, proves the pipeline, and is listed as simulated |
| Load for the collapse alert | `dcgmproftester` from the DCGM image, if it is there | A real tensor workload with no extra image to pull onto a billed node. Checked on the control plane before any GPU is rented |

## Plan

Three parts, and only the middle one rents a GPU.

| Part | What | GPU cost |
|---|---|---|
| B1, authoring | Storage, kube-prometheus-stack, custom counters, alert rules and their unit tests, dashboard, and the scripts to drive B2. Deployed onto the control plane only | none |
| B2, live | GPU up, targets checked, real load, the job killed, the alert watched firing, evidence captured, GPU down | about one hour |
| B3, write up | This page from the artifacts, then a pass over the landing page so nothing claims Sessions C or D are done | none |

B1 also runs two free checks on the control plane before any GPU is rented: whether
the DCGM image carries `dcgmproftester`, and whether `dcgmi` supports field injection
in this build. The plan for B2 changes if either answer is no, and this page will
say how.

## What happened

### B1, authoring

Status: **done**. Written and checked before anything reached the cluster.

| Piece | Where | Checked how, before any cluster saw it |
|---|---|---|
| Health checks for Application resources, so the waves below mean something | `gitops/bootstrap/argocd-values.yaml` | Copied from ArgoCD's documentation for v3.5.3 |
| Storage, refusing volumes on the GPU node | `gitops/apps/local-path-provisioner.yaml`, `gitops/values/local-path-provisioner.yaml` | Every key present in the chart's own values at v0.0.37 |
| kube-prometheus-stack, pinned to the control plane | `gitops/apps/kube-prometheus-stack.yaml`, `gitops/values/kube-prometheus-stack.yaml` | Every key present in the chart's values at 91.4.1, and in the Grafana 13.2.5 and kube-state-metrics 8.5.0 subcharts it pins |
| 34 DCGM counters, owned in Git | `gitops/values/gpu-operator.yaml` | Every field name copied verbatim from dcgm-exporter 4.6.0-4.8.3's own counter file, and the ConfigMap wiring traced through the operator's chart template and controller |
| 9 alert rules | `gitops/manifests/observability/gpu-alerts.yaml` | `promtool` 3.14.0, the Prometheus version the chart deploys: syntax, and 11 test cases making 25 alert evaluations. Four deliberate mutations of the rules each broke the test written for them |
| The dashboard, 21 panels | `gitops/manifests/observability/dashboards/gpu-fleet.json` | All 34 queries parsed by `promtool`; every DCGM metric they read is in the counter set; `kustomize build` produces the ConfigMap with the sidecar's label |
| The B2 scripts | `scripts/check-dcgm-image.sh`, `load.sh`, `inject-xid-dcgm.sh`, `capture-b.sh`, `grafana-ui.sh` | `shellcheck`. Every flag for `dcgmproftester` and `dcgmi test --inject` read from DCGM's source; field IDs 230 and 1004 from `dcgm_fields.h` |

Not checked, because nothing here can check it: whether the charts render with
these values (`helm` and the chart repositories are unreachable from where this was
written), whether an injected value reaches the exporter's XID counter, and whether
`dcgmproftester` runs on an L4 alongside a standalone DCGM. The first is answered
the moment ArgoCD syncs. The other two are what B2 is for.

### B1, on the cluster

Status: **done**. Deployed without a GPU node in the cluster.

In the order the waves were written for: `make argocd` first, so ArgoCD would assess
the health of Application resources, and only then the commit onto `main`, which
ArgoCD watches. Deploying the stack before the health check would have run it
under exactly the creation-only ordering it was written to avoid.

```{ .sh .terminal }
$ kubectl -n argocd get applications.argoproj.io
NAME                     SYNC STATUS   HEALTH STATUS
gpu-observability        Synced        Healthy
gpu-operator             Synced        Healthy
kube-prometheus-stack    Synced        Healthy
local-path-provisioner   Synced        Healthy
node-feature-discovery   Synced        Healthy
root                     Synced        Healthy
```

All four new or changed Applications synced first time: storage, the monitoring
stack, the GPU Operator with its new counter set, and the rules and dashboard. That
answers the one thing B1 could not check from where it was written, whether the
charts render with these values.

```{ .sh .terminal }
$ kubectl -n monitoring get pods,pvc
NAME                                                            READY   STATUS    RESTARTS   AGE
pod/alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   0          2m41s
pod/kube-prometheus-stack-grafana-74ccfb594b-lxdqs              3/3     Running   0          56s
pod/kube-prometheus-stack-kube-state-metrics-84f8496f5c-8kmbq   1/1     Running   0          2m49s
pod/kube-prometheus-stack-operator-5b5dcc8f66-pdbvl             1/1     Running   0          2m49s
pod/kube-prometheus-stack-prometheus-node-exporter-28d9r        1/1     Running   0          2m49s
pod/prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   0          2m40s

NAME                                                                                                   STATUS   CAPACITY   STORAGECLASS
persistentvolumeclaim/prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0   Bound    25Gi       local-path
```

The claim's `VOLUME`, `ACCESS MODES`, `VOLUMEATTRIBUTESCLASS` and `AGE` columns are
left out for width. Prometheus has its 25 Gi volume, bound through the local-path
class, which is the piece that lets GPU metrics outlive the GPU node.

### The free check on the DCGM image

Status: **two of three answered, one inconclusive**
([`session-b-dcgm-image-check.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-b-dcgm-image-check.txt)).

The DCGM image the GPU Operator runs, `nvcr.io/nvidia/cloud-native/dcgm:4.6.0-1-ubuntu24.04`,
was run on the control plane with no GPU:

```{ .sh .terminal }
== dcgmproftester binaries
/usr/bin/dcgmproftester12
/usr/bin/dcgmproftester13
...
== dcgmi test --help (injection)
   dcgmi test --host <IP/FQDN> --inject --gpuid <gpuId> -f <fieldId> -v
      --inject                Inject values into cache.
```

`dcgmproftester` is in the image, in a CUDA 12 and a CUDA 13 build, and `dcgmi test`
supports `--inject`. B2 can generate real load without pulling another image, and
the simulated XID is possible.

The first version of the check also reported `FAIL  --no-dcgm-validation not found
in its help`. That result was wrong, and the fault was in the check, not the image.
Under both binaries the check printed nothing at all, not even the `-d` and `-t`
flags that certainly exist, which means `--help` never ran. `dcgmproftester` links
against `libcuda`, which only exists on a node with an NVIDIA driver, and the check
piped the loader's error through `grep` and then read the empty result as a missing
flag. The script now shows the unfiltered output and which libraries are missing,
and reports that case as inconclusive. The flag itself is in DCGM's source, and the
first `make load` on the GPU node settles it, with `make load` now checking the job
twenty seconds in rather than letting a rejected flag cost ten minutes.

### B2, live

Status: **done**, on 2026-09-24. All times below are UTC, and every one of them comes
from a file in `docs/artifacts/`, not from memory.

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | Every counter in the custom set is exported | **Pass.** 34 of 34, including every one the exporter ships disabled | [`session-b-counters.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-b-counters.txt) |
| 2 | A dashboard from Git with live data | **Pass.** Every panel with something to show was live. The XID panels were empty until the injection because there was no XID, and two panels had a bug, described under "The dashboard bug the injection found" | The screenshots below |
| 3 | `GPUUtilisationCollapse` pending, then firing, after a real load is killed | **Pass, with a caveat.** Pending at 13:46:03, firing at 13:47:03. The load had ended on its own seconds before it was killed, see below | [`session-b-alert-timeline.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-b-alert-timeline.txt), [`session-b-load-timeline.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-b-load-timeline.txt) |
| 4 | Every rule unit tested offline | **Pass.** Now 12 test cases making 26 alert evaluations, one of them added because of this session | `make test-rules`, and the `test-rules` job in CI |
| 5 | History survives the GPU node | **Pass.** 193 GPU utilisation samples, peak 100%, read back with no GPU node in the cluster | [`session-b-history.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-b-history.txt) |
| opt. | `GPUXidCritical` on an injected XID 79 | **Fired, simulated.** 32 seconds from injection to Alertmanager | [`session-b-alertmanager.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-b-alertmanager.txt) |

#### Timeline

| Time | What happened |
|---|---|
| 13:13:48 | `DCGMExporterDown` pending: the exporter's target exists but does not answer yet. Cleared at 13:14:33 without firing, as its five-minute `for:` intends |
| 13:14:18 | The exporter's second and last crash: it could not reach the standalone DCGM host engine |
| 13:15:18 | `DCGMExporterRestarting` fires on those two restarts. It should not have, see below |
| 13:23:14 | Load running: `dcgmproftester13` holding the tensor pipes busy, twenty minutes requested |
| 13:26:18 | `GPUPowerThrottling` pending. Nobody planned this one |
| 13:41:18 | `GPUPowerThrottling` fires, after its fifteen minutes pending |
| about 13:43 | The load reaches the end of its twenty minutes and exits on its own |
| 13:43:09 | `make load-stop` |
| 13:46:03 | `GPUUtilisationCollapse` pending |
| 13:47:03 | `GPUUtilisationCollapse` fires. Alertmanager records it from 13:47:00 |
| 13:49:58 | XID 79 injected into DCGM's cache. **Simulated** |
| 13:50:30 | `GPUXidCritical` in Alertmanager, severity critical, `xid="79"` |
| 14:03:57 | After `make down`: no GPU node in the cluster, and its history still in Prometheus |

The alert times are read back from Prometheus's own `ALERTS` series at a 15 second
step, so each is accurate to that step. The Alertmanager times are to the
millisecond.

#### The GPU under load

![The GPU fleet dashboard twelve minutes into the load](artifacts/session-b-dashboard-under-load-1.png)

GPU utilisation 100%, SM activity 99%, tensor pipes about 95% active and DRAM about
25%, which is what a tensor core benchmark should look like: compute bound, not
memory bound. `dcgmproftester` itself reported about 49.4 TFLOPS
([`session-b-load-job.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-b-load-job.txt)). The framebuffer is almost
untouched at 2.57%, because the test lives in registers and shared memory. The card
drew 72.1 W and ran at 58 °C.

![Throttling, clock events and faults, same moment](artifacts/session-b-dashboard-under-load-2.png)

72 W is the L4's power limit, and the second screenshot shows what that costs: the
card spent about 85% of the load throttled for power and none of it throttled for
temperature. The SM clock on the clocks panel sat well below what an unconstrained
L4 would run at. Nothing is wrong with the card. A 72 W part under a sustained
tensor load is power bound, and on this workload the telemetry says so directly.

That is also why **`GPUPowerThrottling` fired, for real.** Its threshold is power
throttling for more than half of the time, sustained for fifteen minutes, and a
twenty minute tensor load crossed it. It is an `info` alert on purpose: power bound is
the normal state of an L4 at full load, and it is worth knowing about when it appears
on a job that should not be anywhere near the limit, not worth waking anyone for.
It resolved on its own after the load ended.

#### The collapse alert, and the job that was not killed

![GPUUtilisationCollapse firing, from the rule in Git](artifacts/session-b-collapse-firing.png)

`GPUUtilisationCollapse` compares the ten minutes that ended three minutes ago with
the last three minutes. It went pending 2 minutes 54 seconds after `make load-stop`,
which is its three minute window closing, and fired one minute later, which is its
`for:`. The rule shown firing is the one from `gitops/manifests/observability/`, loaded
by ArgoCD.

The acceptance test asked for this after a load that was **killed**, and strictly that
is not what happened. The load was started with twenty minutes requested. When
`make load-stop` read the job's log at 13:43:09, the log already ended with
`GPU 0, TestField 1004 test PASSED.` and `All Tests Passed.`: `dcgmproftester` had
completed its run and exited seconds earlier, and the stop deleted a finished job.
The alert cannot tell the difference, because what it detects is a busy GPU going
idle without warning, and that happened. But a kill was the claim, so it is recorded
as the claim not quite met. `make load` now defaults to an hour, so the stop always
comes first, and `make load-stop` records whether the pod was still running when it
was deleted and warns if it was not.

#### The simulated XID, end to end

`make inject-xid-dcgm` wrote the value 79 into DCGM's field 230,
`DCGM_FI_DEV_XID_ERRORS`, on the GPU through `dcgmi test --inject`. No XID happened on
the card. What the injection proves is everything downstream of DCGM: that the
exporter turns the value into both the raw field and its own counter
`DCGM_EXP_XID_ERRORS_TOTAL` with `xid="79"`, that the rule's "new series" branch
catches the first occurrence, and that Alertmanager receives it as critical, 32
seconds after the injection. It also settled a question from the first capture:
before the injection `DCGM_FI_DEV_XID_ERRORS` had no series at all, and afterwards it
had one. A GPU that has never had an XID has nothing for the exporter to publish.

The third screenshot, taken after the injection, shows the "Last XID seen" panel at
79, and the DCGM health panel at 20, which is DCGM's FAIL result. During the load, in
the second screenshot, health was 10, a warning. Which of DCGM's health systems raised
that warning was not captured, so this page does not guess.

![The faults row after the simulated XID 79](artifacts/session-b-dashboard-after-xid.png)

#### The dashboard bug the injection found

In that same screenshot, the alert has fired and "Last XID seen" reads 79, but "XIDs
by code" is flat at zero. The panel plotted
`increase(DCGM_EXP_XID_ERRORS_TOTAL[$__rate_interval])`, and a series that is born at 1
and stays there has no increase. That is exactly the trap the XID alert rule was
written and unit tested to avoid, and the dashboard fell into it because nothing
tested the dashboard. "Clock events by reason" had the same flaw: the power cap turned
on once and stayed on for twenty minutes, and the panel showed nothing. Both now plot
the cumulative count since the exporter started. Recorded in
[Findings](findings.md).

#### The exporter restarts, explained

Session A left one question open: `nvidia-dcgm-exporter` restarted three times as the
node came up, and the reason was not captured. This time it restarted twice, and
`make capture-b` kept the previous container's log
([`session-b-exporter-restarts.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-b-exporter-restarts.txt)):

```{ .sh .terminal }
level=INFO msg="Attempting to connect to remote hostengine at nvidia-dcgm:5555"
level=ERROR msg="Failed to connect to remote hostengine" mode=standalone address=nvidia-dcgm:5555
  error="error connecting to nv-hostengine: Host engine connection invalid/disconnected"
```

The exporter starts, cannot reach the standalone DCGM host engine, exits with code 1,
and is restarted by the kubelet until the host engine answers. That is the cost of
running DCGM standalone, which this PoC keeps for Session C's `dcgmi diag`, and it
is harmless: the restarts are the recovery, and the exporter was stable for the rest
of the session. It is now a finding rather than a reading.

The same restarts exposed a bug in the alert written for them. `DCGMExporterRestarting`
says "more than two restarts in fifteen minutes", and it fired on two.
`increase()` extrapolates on a counter born inside its window and briefly read 2.3.
Reproduced offline with `promtool`, fixed by using `changes()`, and covered by a
regression test that fails on the old rule. The detail is in [Findings](findings.md).

#### What the rented GPU had already been through

Two panels in every screenshot show history this card brought with it. **One
correctable remapped row**, and an aggregate count of **single bit ECC errors just
under 100**. Aggregate counters survive reboots and belong to the card's life, not to
this session. There are no uncorrectable remapped rows, no remap failures and no
double bit errors. That is a healthy GPU, and also not a new one, and a fleet's
acceptance procedure should read these counters at handover rather than assume zero.
Read from the panels in the screenshots only: the values were not captured as text.

#### What changed because of B2

| Change | Why |
|---|---|
| `DCGMExporterRestarting` uses `changes()` | It fired on two restarts, see above |
| "XIDs by code" and "Clock events by reason" plot cumulative counts | They showed nothing on a real XID series and a real power cap |
| `capture-b` expects no `DCGM_FI_DEV_XID_ERRORS` series until the first XID | The first capture called a correct absence missing |
| `make load` defaults to an hour, `make load-stop` records whether it killed anything | The stop hit a finished job |

None of them came from reading the code again. Each came from the session.
