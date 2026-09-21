# Findings

Gotchas, wrong first assumptions and things that cost time. Kept because a PoC with
no surprises in it was not really run.

## Before the first session

**DCGM exporter ships inside the GPU Operator.** It does not need separate deployment.
It is the `dcgmExporter` subchart and it is enabled by default. The work is configuring
it, not installing it.

**Most of the metrics this PoC needs are off by default.** `DCGM_FI_DEV_XID_ERRORS` is
active in the default counter set, but every ECC metric, every violation and throttle
metric, and `DCGM_EXP_CLOCK_EVENTS_*` are commented out in dcgm-exporter's
`default-counters.csv`. The Session B dashboard is impossible without a custom counters
ConfigMap. Verified against
[the file itself](https://github.com/NVIDIA/dcgm-exporter/blob/main/etc/default-counters.csv),
not from memory.

**The XID gauge is not a reliable alerting signal on its own.** `DCGM_FI_DEV_XID_ERRORS`
reports the value of the last XID encountered and does not reset after recovery unless
dcgm-exporter restarts
([dcgm-exporter issue 500](https://github.com/NVIDIA/dcgm-exporter/issues/500)), and some
codes such as XID 62 are never exported at all
([DCGM issue 235](https://github.com/NVIDIA/DCGM/issues/235)). This is why detection in
Session C reads the kernel log and treats DCGM as corroboration rather than the source
of truth. It is a design decision, not a workaround.

**The Scaleway GPU image choice matters.** `ubuntu_jammy_gpu_os` ships with NVIDIA
drivers preinstalled. Using it would take the driver lifecycle away from the GPU
Operator, which is the single thing this PoC exists to demonstrate. Plain
`ubuntu_jammy` is used instead.

## During the build

To be filled in as things break.
