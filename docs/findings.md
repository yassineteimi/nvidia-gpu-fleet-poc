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

**Confirmed during Session A, on a CPU node, for nothing.** The control plane's
virtio NIC came back labelled `feature.node.kubernetes.io/pci-1af4.present`, vendor
only, with no device class in the label. That is the same code path that will later
produce `pci-10de.present` for an L4. Had `deviceLabelFields` not taken, the label
would have read `pci-0200_1af4.present` and the GPU node would have arrived a week
later carrying `pci-0300_10de.present` while every GPU Operator component waited for
a label that never comes. Worth generalising: a configuration that decides whether
GPU scheduling works can often be tested against whatever hardware is already in the
cluster, days before the expensive hardware shows up.

## During the build

**The ArgoCD initial admin password is rejected, and the password is fine.** The
documented way to read it is to decode `argocd-initial-admin-secret` with
`base64 -d`, which emits the password with no trailing newline. The shell prompt
then renders flush against the last character, and selecting the line takes the
prompt with it. The login fails, the credentials look correct, and there is nothing
to debug because nothing is broken. Cost about twenty minutes before the cause was
obvious. Two smaller traps sit behind it: `base64 -d` is GNU, and macOS wanted `-D`
until recently, so on a Mac the command may not run at all; and `server.insecure` is
set in our values, so the UI is HTTP and a browser pointed at HTTPS fails in a way
that looks unrelated. `make argocd-ui` now prints the password on a line of its own,
uses `go-template` with `base64decode` instead of `base64`, and says which scheme to
use.

The same secret also goes stale silently. ArgoCD leaves
`argocd-initial-admin-secret` in place after the admin password is changed, and a
repeated `helm upgrade` can regenerate the bcrypt hash in `argocd-secret` without
touching it. The failure mode is identical to the one above, correct credentials
flatly rejected, so `make argocd-ui` compares the secret's creation time against
`admin.passwordMtime` and says when the password it just printed is no longer real.

**`fuser` is not on a minimal Ubuntu cloud image.** The common way to wait out
`unattended-upgrades` before running `apt-get` on a fresh node is to poll
`fuser /var/lib/dpkg/lock-frontend`. `fuser` ships in `psmisc`, which a minimal cloud
image does not install, so the poll fails instantly, returns success, and the
`apt-get` behind it walks straight into the lock it was supposed to wait for. The
retry loop around it then hides the problem as an occasional slow boot. Found while
hardening the bootstrap rather than by it failing, which is the only reason it is not
still in there. Replaced with `DPkg::Lock::Timeout`, which apt 2.4 on Jammy supports
and which actually blocks.
