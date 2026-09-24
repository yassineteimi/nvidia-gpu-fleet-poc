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
Operator, which is the single thing this PoC exists to demonstrate. The plan was
plain `ubuntu_jammy` instead. That plan did not survive contact with the API: see
the first entry under "During the build".

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

**And the rest, confirmed on the L4 itself.** When the GPU node joined on 2026-09-24
it was labelled `pci-10de.present=true`, and GPU Feature Discovery's `nvidia.com/*`
labels appeared on it: product, family, compute capability, driver version. Those
only exist because of `extraLabelNs: [nvidia.com]`, the third of the three
settings, so all three are now proven on the hardware they were written for.

## During the build

**ArgoCD sync waves between child Applications do not wait for anything by
default.** This repository's wave table said Node Feature Discovery syncs in wave 0
and the GPU Operator in wave 1, and the architecture page described that as an
ordering. It was not one. ArgoCD stopped assessing the health of `Application`
resources in version 1.8, and its own documentation says that anyone using waves
across an app of apps has to restore that health check by hand. Without it, a
later wave's Application is created the moment an earlier one is, healthy or not.
Session A never noticed, because the GPU Operator waits for NFD's labels on its
own, so the missing ordering happened not to matter. Session B would have
noticed: the GPU Operator's ServiceMonitor needs the Prometheus CRDs from an
earlier wave to exist, and nothing was making it wait for them.
`gitops/bootstrap/argocd-values.yaml` now carries the health check, copied from
[ArgoCD's documentation](https://github.com/argoproj/argo-cd/blob/v3.5.3/docs/operator-manual/health.md)
for the version this cluster runs. Found by reading the documentation while
planning Session B, not by a failure, which is the only reason this entry is not
about a broken sync.

**`increase()` cannot see the first XID.** dcgm-exporter 4.8.3's
`DCGM_EXP_XID_ERRORS_TOTAL` is the right signal for XID alerts: a real counter, one
series per `xid`, counting DCGM events since the exporter started. But a series for
a given XID only comes into existence when that XID first happens, and it is born
at 1. `increase()` needs two samples and sees a counter that starts at 1 and stays
there as no increase at all, so the obvious rule,
`increase(DCGM_EXP_XID_ERRORS_TOTAL[5m]) > 0`, stays silent for exactly the first
fatal XID on a node, which is usually the only one there is before the node is
lost. The rule in `gitops/manifests/observability/gpu-alerts.yaml` has a second
branch that fires on a series which exists now and did not five minutes ago. The
unit tests include that case, and replacing the rule with the naive one makes
that test fail, which was checked rather than assumed.

**`increase()` also counts restarts that did not happen.** The same function has the
opposite problem on a counter that is born partway through the window, and this
one was found live rather than on paper. In Session B the DCGM exporter restarted exactly twice
while the GPU node came up, and `DCGMExporterRestarting`, then written as
`increase(kube_pod_container_status_restarts_total{...}[15m]) > 2`, fired. A restart
counter belongs to a pod, so it starts inside the window, and `increase()`
extrapolates from the samples it has towards the window's edges. Just after two
quick restarts that gives about 2.3 rather than 2, for a few evaluations, and a rule
with no `for:` fires on the first one. Reproduced offline with `promtool` before the
rule was touched. The rule now uses `changes()`, which counts the steps that
happened, and a regression test replays two quick restarts on a new pod: it passes
with `changes()` and fails with `increase()` put back. The general point, for any
small integer threshold: `increase()` is a rate estimate, not a count.

**Which XIDs mean a broken GPU is already decided in code.** The list of XIDs that
are application errors rather than GPU faults is a judgement call that is easy to
write from memory and get subtly wrong. The NVIDIA device plugin the GPU Operator
deploys already makes it, in `internal/rm/health.go` at v0.20.0: 13, 31, 43, 45, 68
and 109 are "application errors: the GPU should still be healthy", and any other
XID marks the GPU unhealthy. The alert rules use the same line, so Prometheus and
the scheduler cannot disagree about whether a GPU is broken.

**Scaleway will not boot plain Ubuntu on a GPU instance.** The first `make up`
failed before any GPU was billed:

```text
could not get image 'fr-par-2/ubuntu_jammy': couldn't find a local image
for the given zone (fr-par-2) and commercial type (L4-1-24G)
```

GPU instance types only accept images the marketplace flags as compatible with
them. Asking the marketplace directly (`make gpu-images`) for everything compatible
with `L4-1-24G` in fr-par-2 returned exactly four labels:

| Label | What it is |
|---|---|
| `ubuntu_jammy_gpu_os_12` | GPU OS, NVIDIA driver preinstalled |
| `ubuntu_noble_gpu_os_12` | GPU OS, NVIDIA driver preinstalled |
| `ubuntu_noble_gpu_os_13_nvidia` | GPU OS, NVIDIA driver preinstalled |
| `kapsule_noble` | Scaleway's managed Kubernetes node image |

No plain `ubuntu_jammy`, no plain `ubuntu_noble`. The pre-session plan assumed a
plain image existed and the Terraform validation was written to refuse only the
`gpu_os` ones, which was the right refusal pointed at an option that was never
there.

The way out was in Scaleway's own documentation for its managed Kubernetes. On
Kapsule GPU pools, "the GPU Operator installs the drivers shortly after node
creation": the node boots `kapsule_noble` without a driver and the operator puts
one there. That is precisely the pattern this PoC demonstrates, done by the
provider itself, so the GPU node now boots `kapsule_noble`. The driver lifecycle
stays with the GPU Operator and stays pinned in Git.

Two costs, both stated rather than hidden. The GPU node runs Ubuntu 24.04 while
the control plane stays on 22.04, which Kubernetes does not mind but which is a
mixed fleet. And `kapsule_noble` is built for Scaleway's managed clusters, not for
kubeadm, so it may arrive carrying its own container runtime or Kubernetes
components. The bootstrap now records an inventory of what the image shipped
before changing anything, and checks for a driver before installing anything, so
a surprise costs one minute of L4 time rather than ten.

In the event there was no surprise. The inventory showed a bare Ubuntu 24.04:
no container runtime, no Kubernetes packages, no NVIDIA driver, only the in-kernel
`nouveau` module attached to the L4. The GPU Operator built and loaded `595.91.07`
onto it and the acceptance test passed. See [Session A](01-platform.md).

With `kapsule_noble` the next `make up` got further, past image resolution, and
stopped one step later on something no image choice fixes:

```text
quota exceeded(s): cp_servers_type_L4_1_24G has reached its quota (0/0)
```

Scaleway's quota for `L4-1-24G` is zero for an Organization with a validated payment
method and one once its identity is also verified. The prerequisites page had
claimed GPU instances in fr-par-2 "need no quota request in practice". That was
written from general impressions, not from Scaleway's quota table, and it was
wrong. The page now says what the table says. The useful side of the failure is
that it proves `kapsule_noble` is accepted for an L4: the image lookup is what
failed before, and this time it passed.

Querying the marketplace had its own trap: the `local-images` endpoint returns
`400` unless exactly one of image ID, version ID or image label is set, so it cannot
be asked "what is in this zone" in one call. The first version of `make gpu-images`
was written from memory and got a `400` on every page. The second was written from
the request struct in Scaleway's Go SDK.

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
