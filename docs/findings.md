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

**Deploying NFD separately means inheriting the GPU Operator's NFD configuration.**
Setting `nfd.enabled=false` and running Node Feature Discovery as its own ArgoCD
Application is the tidy choice, but the chart default and the GPU Operator's default
are not the same thing, and the difference is silent. NFD's own default
`sources.pci.deviceLabelFields` is `[class, vendor]`, which labels a GPU node
`feature.node.kubernetes.io/pci-0300_10de.present`. Every GPU Operator component
selects on `feature.node.kubernetes.io/pci-10de.present`, which only appears when
`deviceLabelFields` is `[vendor]`. Get this wrong and the labels are all there, they
are just not the labels anything is looking for: the operator syncs green and
schedules nothing. Two more settings travel with it, `sources.pci.deviceClassWhitelist`
and `master.config.extraLabelNs: [nvidia.com]`, the latter because GPU Feature
Discovery publishes into a namespace NFD's master rejects unless told otherwise.
Compared against the operator's own
[subchart values](https://github.com/NVIDIA/gpu-operator/blob/v26.7.0/deployments/gpu-operator/values.yaml)
rather than guessed, and written into
[`gitops/values/node-feature-discovery.yaml`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/gitops/values/node-feature-discovery.yaml)
with the reasoning next to it.

## During the build

To be filled in as things break.
