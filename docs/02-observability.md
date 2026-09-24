# Session B: observability and XID alerting

!!! info "Status: planned, not yet run"
    This chapter is written during the session, from output captured live, not
    reconstructed afterwards. Until the session has run, this page states the plan,
    the decisions behind it and the acceptance test only. Nothing is claimed here
    that has not happened.

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

To be filled in during Session B with real captured output.
