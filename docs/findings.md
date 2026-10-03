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

### A GPU with no XIDs has no XID metric at all

The burn-in's XID query came back with no data, not a zero, which looked like broken
telemetry on a GPU that was otherwise reporting everything. It isn't. DCGM keeps the
XID field blank until the GPU records an XID, and dcgm-exporter at 4.6.0-4.8.3 drops
any blank value before it becomes a sample (`internal/pkg/collector/gpu_collector.go`,
`toString`, which checks `isInt64Blank`). Session B had a series only because I'd
injected XID 79 into DCGM before that capture ran. The `GPUXidCritical` alert is fine
with this, since it fires on a value that exists. A check that wants "no XID" has to
treat no data as zero, and it's safer to pair it with a source that always exists:
the burn-in capture now also reads node-problem-detector's `GPUUnhealthy` condition
through kube-state-metrics.

The same capture taught me to read units off the counter file, not my memory:
`DCGM_FI_DEV_POWER_VIOLATION` and `DCGM_FI_DEV_THERMAL_VIOLATION` count nanoseconds.
My first capture labelled them microseconds and reported 99.7% of three hours as
10.6 trillion µs.

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

## node-problem-detector and the remediation controller

### node-problem-detector freezes a condition's message

Once a permanent condition is True with a given reason, node-problem-detector
`v1.36.0` doesn't update its message, however many more matching lines arrive. My
first design had one condition for every XID and let the controller classify the code
from the message. An XID 13 (an application error) followed by an XID 79 would have
left the message on 13, and the broken GPU would never have been drained. The fault
or application split now lives in the rule, with a test that feeds 13 and then 79.

Two more from the same reading: it trims every kernel log line, so a driver line
ending in `79, ` arrives as `79,`, and its own deployment manifest at the `v1.36.0` tag
still references image `v0.8.19`.

### A controller acting on watch events can act on a stale node

In Session C my controller announced one drain three times. The node watch events
that queued up while it was draining carried the node as it was before its own
`drained-at` annotation, so each one looked like a node that still needed draining;
the controller found no pods and emitted `GPUNodeDrained` again. It didn't evict
anything twice, because there was nothing left, but a cordon or an eviction decided
from a stale copy is exactly the kind of thing that does damage on a bigger fleet.
The controller now reads the node from the API before acting on anything that looks
unhealthy, and two regression tests feed it the stale copy.

### A kernel log timestamp isn't a wall clock time

node-problem-detector dates each kernel log record from the kernel's uptime counter,
and that date becomes the condition's `lastTransitionTime`. On my control plane, six
days after boot, it came out 4 seconds earlier than the moment node-problem-detector
actually handled the line; on a GPU node booted 16 minutes earlier, 1 second. Fine for
knowing roughly when a fault happened, wrong for measuring a sub-second reaction. I
timed Session C from the node's wall clock at the moment of injection and the
controller's own millisecond annotations instead.

## GPU Operator and Node Feature Discovery

### A time slicing change under the same name never reaches the device plugin

The device plugin's config-manager at `v0.20.0` watches one thing: the node label
`nvidia.com/device-plugin.config`. It doesn't watch the ConfigMap. If I'd changed
`replicas: 4` to `replicas: 2` under the same config name, the ConfigMap would have
changed in Git and in the cluster, ArgoCD would have shown everything in sync, and the
plugin would have kept advertising 4. So the config is named after what it does,
`ts-4`, and a different split gets a new name. I found this in `cmd/config-manager`
before the first GPU sitting, not after.

It helps to parse the config with the plugin's own code, too. The loader is lenient
about the case of field names but not about their spelling: `timeSharing` instead of
`timeSlicing` fails, and so does `replicas: 1`. `make test-time-slicing` runs the
`v0.20.0` loader on the exact block in the values file.

## Object storage

### MinIO isn't maintained any more

I'd planned the checkpoint store on MinIO. Its GitHub repository now says it's no
longer maintained, and the community edition is published as source only, with no
image to pin. I switched to Garage `v2.4.1`, which runs as a single node and takes
its first bucket and key from environment variables.

### Garage's Helm chart can't keep its secret under ArgoCD

The chart creates its RPC secret with `lookup`, reusing the existing value if there is
one. ArgoCD renders charts with `helm template`, where `lookup` always returns nothing,
so the chart would generate a new secret on every sync. Its single node mode also
hardcodes the server arguments. I wrote five plain manifests instead, and a bootstrap
Job creates the secrets once inside the cluster, so they're never in Git.

## Training jobs

### A non-root PyTorch image dies building its optimizer

The first training Job on the L4 died in under a second: `getpwuid(): uid not found:
65532`. Creating `torch.optim.SGD` at torch 2.11 imports `torch._dynamo`, which names
an Inductor cache directory after `getpass.getuser()`, and that looks the uid up in
`/etc/passwd` unless `USER` or `LOGNAME` is set. My image runs as 65532 with no passwd
entry, which is normal for a distroless-style non-root image, and nothing is ever
compiled, yet constructing the optimizer is enough. The tenancy pods, running plain
tensor maths as the same uid, never hit it. The image build's smoke test missed it
too, because it ran before the `USER` line, as root. `USER` is now set in the Job and
the image, and the smoke test runs as the image's user.

### The PyTorch runtime image isn't a conda image any more

I wrote the trainer's Dockerfile expecting the conda layout I remembered, and the first
CI build failed on `pip install`. `pytorch/pytorch:2.11.0-cuda12.8-cudnn9-runtime` is
Ubuntu 24.04 with torch in the system Python 3.12, which refuses pip installs by
default (PEP 668), and there's no `python` command, only `python3`. The entry point
and every pod command in the scripts would have failed on the GPU node too. The image
now installs with `--break-system-packages`, calls `python3`, and runs the backend on
CPU during the build, so the next surprise of this kind stops CI rather than a billed
session.

### The last seconds of an evicted run disappear unless you flush on the way out

The trainer writes a step log to the bucket every 5 seconds, because the evicted pod,
and its container log, are deleted by the eviction. The end to end test against a real
Garage server interrupted a run at step 130 and resumed from the checkpoint at 100. It
expected 30 redone steps and found 28: the steps since the last flush were gone, and
the goodput analysis would have counted them as outage instead. The loop now flushes on
any exit, and SIGTERM is turned into a normal exit so that flush runs. A node that dies
outright can still lose up to 5 seconds of log, and the analysis says so.

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

### An L4 shortage in one zone doesn't have to move the cluster

In Session D, `make up` failed with `L4-1-24G is out of stock` in fr-par-2. My
documented fallback, pl-waw-2, moves both nodes and the Private Network, which would
have rebuilt the control plane and lost etcd, ArgoCD, the Prometheus history and the
checkpoint store. Private Networks are regional, though, so the GPU node can sit in
another zone of fr-par and still join over the private network. A `gpu_zone` variable
now moves only the GPU node's four zonal resources: its IP, the server, its private
NIC and its security group. The node joined across zones and ran all of D2a from fr-par-1,
checkpoints to fr-par-2 included, at 2.0 to 2.5 s per write of roughly 270 MB (my estimate from the model size).

### A GPU that can't boot still leaves a volume billing

fr-par-1 listed the L4 as `scarce`, so I tried it. Terraform created the server, asked
Scaleway to power it on, and got it back stopped: `expected state running but found
stopped`, with an empty `state_detail`. Minutes later the zone read `shortage`, so it
was capacity, not configuration. The expensive part came after. Scaleway had created
the 150 GB root volume from the image but never attached it, so the server's state had
no volume ID, and `make down` failed with `volume ID not found`. The volume was still
there and billing, and Terraform had no idea it existed. I found it by listing the
zone's block volumes, deleted the server and the volume through the API, removed the
server from the Terraform state and ran `make down` again for the IP.

It had happened once already, and I didn't know. The very first attempt that day, in
fr-par-2, failed with `out of stock` and left its own 150 GB volume behind. I only
found it three days later, after destroying the whole cluster, when a last sweep of
both zones still showed one volume: created at 14:21 on 2026-09-30, the minute of that
first failure. My leftover check had been looking only at the GPU node's current zone,
which by then was fr-par-1.

`make down` now asks the API what's left in every zone of the region every time it
runs, whether the apply worked or not: a server with the node's name, and any block
volume with nothing attached. It prints them with the delete commands. It doesn't delete
them: a volume picked by name alone is a guess, and a wrong guess deletes something
that isn't mine.

Scaleway's availability API (`/instance/v1/zones/<zone>/products/servers/availability`)
left `L4-1-24G` out of fr-par-2's list entirely during the shortage, rather than
reporting it as `shortage`. A missing entry there means "none right now", not
necessarily "never offered".

## Node bootstrap

### `fuser` isn't on a minimal Ubuntu cloud image

The usual way to wait for `unattended-upgrades` before running `apt-get` on a fresh
node is to poll `fuser /var/lib/dpkg/lock-frontend`. `fuser` comes from `psmisc`, which
minimal cloud images don't install, so the poll fails instantly, returns success, and
`apt-get` runs straight into the lock it was meant to wait for. The retry loop around
it then hides that as an occasionally slow boot. I caught it while hardening the
bootstrap, not because it failed, and replaced it with `DPkg::Lock::Timeout`, which apt
2.4 on Jammy supports and which actually blocks.
