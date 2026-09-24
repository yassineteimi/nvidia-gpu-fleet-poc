# Findings

Things that didn't behave the way the documentation or my first assumption said, and
what I changed because of them. Grouped by component, with the most useful first.

## Prometheus and DCGM

### `increase()` misses the first XID on a node

dcgm-exporter 4.8.3's `DCGM_EXP_XID_ERRORS_TOTAL` is the right signal for XID alerts:
a real counter, one series per `xid`, counting DCGM events since the exporter started.
The catch is that a series only appears when its XID first happens, and it starts at
1. `increase()` needs two samples and reads a counter that starts at 1 and stays there
as no increase. So the obvious rule, `increase(DCGM_EXP_XID_ERRORS_TOTAL[5m]) > 0`,
stays silent on the first fatal XID on a node, which is usually the only one before
the node is lost.

The rule in `gitops/manifests/observability/gpu-alerts.yaml` has a second branch that
fires on a series that exists now and didn't five minutes ago. A unit test covers that
case, and I checked that swapping in the naive rule makes it fail.

I then made the same mistake on the dashboard, which had no tests. In Session B the
injected XID 79 fired the alert and "Last XID seen" read 79, but "XIDs by code", built
on `increase()`, stayed at 0. "Clock events by reason" did the same during a power cap
that lasted 20 minutes. Both panels now plot the cumulative count.

### `increase()` also over-counts restarts

The same function goes wrong the other way on a counter that starts partway through
its window, and I only found this one live. In Session B the DCGM exporter restarted
exactly twice while the GPU node came up, and `DCGMExporterRestarting`, written then as
`increase(kube_pod_container_status_restarts_total{...}[15m]) > 2`, fired. A restart
counter belongs to a pod, so it starts inside the window, and `increase()` extrapolates
towards the window's edges. Just after two quick restarts that gives about 2.3, for a
few evaluations, and a rule with no `for:` fires on the first one.

I reproduced it offline with `promtool` before touching the rule. It now uses
`changes()`, which counts the steps that actually happened, and a regression test
replays two quick restarts on a new pod: it passes with `changes()` and fails with
`increase()`. For any small integer threshold, treat `increase()` as a rate estimate,
not a count.

### The exporter restarts at startup because of standalone DCGM

Session A saw three restarts and I could only guess why. In Session B I captured the
previous container's log: `Failed to connect to remote hostengine at nvidia-dcgm:5555`,
exit code 1. With `dcgm.enabled: true`, the exporter is a client of a separate host
engine pod, starts without waiting for it, and crash loops until it answers. It's
harmless, since the restarts are the recovery. But it's the price of standalone DCGM,
and any alert on exporter restarts has to tolerate a couple at every node start.

### Most of the metrics I needed are off by default

The DCGM exporter ships inside the GPU Operator as the `dcgmExporter` subchart, enabled
by default, so the work is configuring it rather than installing it. And the default
configuration isn't enough. `DCGM_FI_DEV_XID_ERRORS` is in the default counter set,
but every ECC metric, every violation and throttle metric, and
`DCGM_EXP_CLOCK_EVENTS_*` are commented out in dcgm-exporter's
[`default-counters.csv`](https://github.com/NVIDIA/dcgm-exporter/blob/main/etc/default-counters.csv).
The Session B dashboard needs a custom counter ConfigMap.

### The XID gauge can't carry an alert by itself

`DCGM_FI_DEV_XID_ERRORS` holds the last XID seen and doesn't reset after recovery
unless dcgm-exporter restarts
([dcgm-exporter issue 500](https://github.com/NVIDIA/dcgm-exporter/issues/500)). Some
codes, like XID 62, are never exported at all
([DCGM issue 235](https://github.com/NVIDIA/DCGM/issues/235)). That's why Session C's
detection reads the kernel log and only uses DCGM to corroborate. It's a design choice
I'd make on a real fleet too.

### The device plugin already decides which XIDs mean a broken GPU

Which XIDs are application errors and which are GPU faults is a judgement call that's
easy to get subtly wrong from memory. The NVIDIA device plugin the GPU Operator deploys
already makes it, in `internal/rm/health.go` at v0.20.0: 13, 31, 43, 45, 68 and 109 are
"application errors: the GPU should still be healthy", and any other XID marks the GPU
unhealthy. My alert rules draw the same line, so Prometheus and the scheduler can't
disagree about whether a GPU is broken.

## GPU Operator and Node Feature Discovery

### Running NFD yourself means copying the operator's NFD settings

Setting `nfd.enabled=false` and running Node Feature Discovery as its own ArgoCD
Application is the tidier choice, but NFD's defaults and the GPU Operator's aren't the
same, and nothing warns you. NFD's own default for `sources.pci.deviceLabelFields` is
`[class, vendor]`, which labels a GPU node
`feature.node.kubernetes.io/pci-0300_10de.present`. Every GPU Operator component
selects on `feature.node.kubernetes.io/pci-10de.present`, which you only get with
`deviceLabelFields: [vendor]`. Get it wrong and the labels are all there, just not the
ones anything is looking for: the operator syncs green and schedules nothing.

Two more settings go with it: `sources.pci.deviceClassWhitelist`, and
`master.config.extraLabelNs: [nvidia.com]`, because GPU Feature Discovery publishes into
a namespace NFD's master otherwise rejects. I took all three from the operator's own
[subchart values](https://github.com/NVIDIA/gpu-operator/blob/v26.7.0/deployments/gpu-operator/values.yaml)
and put them in
[`gitops/values/node-feature-discovery.yaml`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/gitops/values/node-feature-discovery.yaml)
with the reasoning next to them.

I tested the first one without a GPU. The control plane's virtio NIC came back labelled
`pci-1af4.present`, vendor only, which is the same code path that later produces
`pci-10de.present` for the L4. When the GPU node joined on 2026-09-24 it got
`pci-10de.present=true`, and GPU Feature Discovery's `nvidia.com/*` labels appeared,
which only happens with `extraLabelNs`. All three settings are now confirmed on the
hardware they were written for. The general lesson: you can often test the
configuration that decides whether GPU scheduling works against hardware already in
the cluster, days before the expensive hardware arrives.

## ArgoCD

### Sync waves between child Applications don't wait for anything by default

My wave table put Node Feature Discovery in wave 0 and the GPU Operator in wave 1, and
the architecture page called that an ordering. It wasn't. ArgoCD stopped assessing the
health of `Application` resources in version 1.8, and its documentation says that
anyone using waves across an app of apps has to restore that health check themselves.
Without it, a later wave's Application gets created as soon as an earlier one is,
healthy or not.

Session A didn't notice, because the GPU Operator waits for NFD's labels on its own.
Session B would have: the GPU Operator's ServiceMonitor needs the Prometheus CRDs from
an earlier wave, and nothing made it wait. `gitops/bootstrap/argocd-values.yaml` now
carries the health check, copied from
[ArgoCD's documentation](https://github.com/argoproj/argo-cd/blob/v3.5.3/docs/operator-manual/health.md)
for the version this cluster runs. I found this reading the docs while planning
Session B, before it broke anything.

### The initial admin password gets rejected, and there's nothing wrong with it

The documented way to read the password is to decode `argocd-initial-admin-secret`
with `base64 -d`, which prints it with no trailing newline. The shell prompt then
starts right after the last character, and selecting the line copies part of the
prompt with it. The login fails, the credentials look right, and there's nothing
broken to debug. It cost me about twenty minutes.

Two smaller traps sit behind it. `base64 -d` is the GNU flag, and macOS wanted `-D`
until recently, so on a Mac the command may not run at all. And `server.insecure` is
set in my values, so the UI is plain HTTP, and a browser pointed at HTTPS fails in a
way that looks unrelated. `make argocd-ui` now prints the password on its own line,
decodes it with `go-template` and `base64decode`, and tells you which scheme to use.

The same secret can also go stale without warning. ArgoCD leaves
`argocd-initial-admin-secret` in place after the admin password changes, and a repeat
`helm upgrade` can regenerate the bcrypt hash in `argocd-secret` without touching it.
It fails exactly the same way, so `make argocd-ui` compares the secret's creation time
with `admin.passwordMtime` and warns when the password it printed is no longer valid.

## Scaleway

### No plain Ubuntu on a GPU instance

I didn't want `ubuntu_jammy_gpu_os`, because it ships with the NVIDIA driver installed
and would take the driver lifecycle away from the GPU Operator. So I planned for plain
`ubuntu_jammy`. The first `make up` failed before any GPU was billed:

```text
could not get image 'fr-par-2/ubuntu_jammy': couldn't find a local image
for the given zone (fr-par-2) and commercial type (L4-1-24G)
```

GPU instance types only accept images the marketplace flags as compatible. I wrote
`make gpu-images` to ask the marketplace what's compatible with `L4-1-24G` in
fr-par-2, and it returned four labels:

| Label | What it is |
|---|---|
| `ubuntu_jammy_gpu_os_12` | GPU OS, NVIDIA driver preinstalled |
| `ubuntu_noble_gpu_os_12` | GPU OS, NVIDIA driver preinstalled |
| `ubuntu_noble_gpu_os_13_nvidia` | GPU OS, NVIDIA driver preinstalled |
| `kapsule_noble` | Scaleway's managed Kubernetes node image |

No plain `ubuntu_jammy` or `ubuntu_noble`. My Terraform validation refused only the
`gpu_os` images, which was the right refusal aimed at an option that never existed.

Scaleway's own managed Kubernetes documentation had the answer. On Kapsule GPU pools,
"the GPU Operator installs the drivers shortly after node creation": nodes boot
`kapsule_noble` with no driver and the operator installs one. That's the pattern this
PoC is about, used by the provider itself, so the GPU node now boots `kapsule_noble`
and the driver stays with the GPU Operator, pinned in Git.

It has two costs. The GPU node runs Ubuntu 24.04 while the control plane stays on
22.04, which Kubernetes doesn't mind but does make it a mixed fleet. And since
`kapsule_noble` is built for Scaleway's managed clusters, not kubeadm, it might have
arrived with its own container runtime or Kubernetes components. So the bootstrap
records what the image shipped before changing anything, and checks for a driver
before installing anything, which keeps the cost of a surprise to one minute of L4
time. There was no surprise: a bare Ubuntu 24.04 with only the in-kernel `nouveau`
module attached to the L4. The GPU Operator built and loaded `595.91.07` and
acceptance passed ([Session A](01-platform.md)).

Querying the marketplace had its own trap. The `local-images` endpoint returns `400`
unless exactly one of image ID, version ID or image label is set, so you can't ask
"what's in this zone" in one call. My first `make gpu-images`, written from memory, got
a `400` on every page. The second one I wrote from the request struct in Scaleway's Go
SDK.

### The L4 quota is zero until you verify your identity

With `kapsule_noble`, the next `make up` got past the image and stopped one step later:

```text
quota exceeded(s): cp_servers_type_L4_1_24G has reached its quota (0/0)
```

Scaleway's `L4-1-24G` quota is zero for an Organization with a validated payment
method, and one once its identity is also verified. My prerequisites page had said GPU
instances in fr-par-2 "need no quota request in practice". I'd written that from a
general impression instead of Scaleway's quota table, and it was wrong; the page now
says what the table says. The failure did prove one thing: Scaleway accepts
`kapsule_noble` for an L4, because this time the image lookup passed.

## Node bootstrap

### `fuser` isn't on a minimal Ubuntu cloud image

The usual way to wait for `unattended-upgrades` before running `apt-get` on a fresh
node is to poll `fuser /var/lib/dpkg/lock-frontend`. `fuser` comes from `psmisc`, which
minimal cloud images don't install, so the poll fails instantly, returns success, and
`apt-get` runs straight into the lock it was meant to wait for. The retry loop around
it then hides that as an occasionally slow boot. I caught it while hardening the
bootstrap, not because it failed, and replaced it with `DPkg::Lock::Timeout`, which apt
2.4 on Jammy supports and which actually blocks.
