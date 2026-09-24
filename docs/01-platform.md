# Session A: platform and GPU lifecycle

!!! success "Status: done, acceptance test passed on 2026-09-24"
    Every criterion below passed on a real L4. The NVIDIA driver on the node is
    `595.91.07`, the version pinned in Git, installed by the GPU Operator onto an
    image that had no NVIDIA driver at first boot. This chapter was written from
    output captured live, which is committed under `docs/artifacts/`, not
    reconstructed afterwards.

## Scope

Terraform for both nodes. kubeadm control plane with Flannel. ArgoCD installed and
managing this repository from the first commit. Node Feature Discovery and the NVIDIA
GPU Operator deployed through ArgoCD, never by hand. Driver and container toolkit
versions pinned in Git and pilotable from a commit.

## Acceptance test

A `cuda-vectoradd` pod reaches Completed with `Test PASSED`. `nvidia-smi` inside a
CUDA container shows the L4 and the pinned driver version. The node advertises
`nvidia.com/gpu: 1` and carries the NFD label `feature.node.kubernetes.io/pci-10de.present=true`.
No GPU software was installed by hand on the node.

## What is in the repository before the session starts

The code below was written ahead of the session so that the session itself is spent
running and observing rather than typing. None of it has been applied against the
Scaleway API yet. `terraform fmt` and `shellcheck` pass, and the cloud-init templates
have been rendered and syntax checked, which is a different and much weaker claim
than "it works".

```text
terraform/
├── providers.tf              # scaleway/scaleway ~> 2.83, credentials from the environment
├── variables.tf              # every decision that might need changing at 9am on a Saturday
├── locals.tf                 # node names, the private or public address switch
├── network.tf                # VPC, Private Network, IPAM reservations, security groups
├── control-plane.tf          # persistent node
├── gpu-node.tf               # ephemeral node, count driven by gpu_node_enabled
├── outputs.tf
├── terraform.tfvars.example
└── cloud-init/
    ├── common.sh.tftpl       # containerd, kubeadm toolchain, private NIC
    ├── control-plane.sh.tftpl
    └── gpu-node.sh.tftpl

scripts/
├── lib.sh                    # shared helpers, .env loading, SSH, wait loops
├── cluster-up.sh             # private network plus control plane, then the kubeconfig
├── bootstrap-argocd.sh       # the one Helm release a human installs
├── gpu-up.sh                 # create, join, wait for nvidia.com/gpu
├── gpu-down.sh               # cordon, drain, delete, destroy
└── cost-report.sh

gitops/
├── bootstrap/                # argo-cd values and the app of apps
├── apps/                     # node-feature-discovery, gpu-operator
└── values/                   # the values files those Applications reference
```

## Decisions worth defending

### The GPU node boots a driverless image

Scaleway publishes GPU OS images with the NVIDIA driver and container toolkit already
installed. Booting one would work, and it would quietly delete the point of this
project: the driver lifecycle would belong to the image rather than to the GPU
Operator. So there are two gates against it. Terraform refuses any image label
containing `gpu_os`, and the GPU node's own bootstrap script exits non zero if it
finds `nvidia-smi`, `/dev/nvidia0` or a loaded `nvidia` kernel module. The first
checks the intent, the second checks the result, and the second now runs before
anything is installed, because every minute on that node is billed.

The original plan was plain `ubuntu_jammy`. Scaleway does not offer it on GPU
instance types, which the first `make up` discovered. The image actually used is
`kapsule_noble`, the one Scaleway's own managed Kubernetes boots on GPU pools before
its GPU Operator installs the driver. How that was found is in
[Findings](findings.md).

### Node addresses are reserved in IPAM before the nodes exist

The control plane needs to know its own API server address before it boots, because
that address goes into `kubeadm init` as the advertise address, into the certificate
SANs, and into the join endpoint that the GPU node uses days later. Reserving both
private addresses as `scaleway_ipam_ip` resources makes them known at plan time. DHCP
is still tried first on each node and the reservation is configured statically only
if DHCP has not delivered it, so both paths end at the same address.

`node_ip_mode` switches the whole cluster between the Private Network and public
addresses in one variable, which is the escape hatch if Scaleway's Private Network
DHCP misbehaves on the day.

### Flannel is pinned to an interface

On a node with two interfaces, Flannel picks the one holding the default route, which
is the public one. Left alone it would build its VXLAN mesh over the internet while
the kubelet advertises a private address. The control plane bootstrap patches the
DaemonSet with `--iface-can-reach` pointing at the control plane address, so the data
plane follows the same path as everything else.

### The GPU node is a count, not a target

`gpu_node_enabled` defaults to `false`. `gpu-up.sh` writes `gpu_node_enabled = true`
into a gitignored `gpu.auto.tfvars` and applies, `gpu-down.sh` writes `false` and
applies. This is deliberately not `terraform apply -target`. With a toggle, Terraform
holds the truth about whether a GPU is supposed to exist, so a plan run on a Tuesday
reports a node forgotten on Saturday as drift instead of agreeing with it. An L4 left
running for a week costs more than this PoC's entire budget.

### Node Feature Discovery is its own Application

The GPU Operator will deploy NFD itself, and most installations let it. Here `nfd.enabled`
is `false` and NFD is sync wave 0 with its own pinned chart version. The labels NFD
produces are load bearing for the operator's node selectors, for scheduling, and from
Session C for the remediation controller, so they belong in Git where they can be read.
The cost of owning it is having to replicate the configuration the operator's subchart
would have applied, which is written up in [Findings](findings.md).

### The join token is created on demand

`gpu-up.sh` asks the control plane for `kubeadm token create --ttl 30m --print-join-command`
over SSH and runs the result on the new node. No bootstrap token is committed, none is
stored in Terraform state, and `--discovery-token-unsafe-skip-ca-verification` is not used:
the CA hash comes back in the same printed command.

## Open questions for the session

Things that were written down but unverified. Each is struck through as the session
answers it, rather than quietly fixed:

- ~~Whether the NVIDIA Helm repository serves the GPU Operator chart as `v26.7.0` or
  `26.7.0`.~~ **Answered: `v26.7.0`, with the prefix.** The Application syncs.
- ~~Whether NFD produces `pci-10de.present` or `pci-0300_10de.present`.~~
  **Answered: the vendor only form.** Confirmed on a virtio NIC before any GPU
  existed, which made it free.
- ~~Whether `PLAY2-MICRO` is offered in `fr-par-2` at 4 vCPU and 8 GB, and what the
  root volume type constraint is for it and for `L4-1-24G`.~~ **Answered: both run on
  `sbs_volume`.** The L4's root volume came up as a 150 GB SBS volume at 5000 IOPS.
- A question nobody wrote down, answered by the first `make up`: **Scaleway does not
  offer plain Ubuntu on the L4 at all.** The GPU node now boots `kapsule_noble`.
- ~~Whether `kapsule_noble` arrives carrying Kubernetes components that clash with
  kubeadm.~~ **Answered: it carries nothing to clash with.** No container runtime,
  no Kubernetes packages, no NVIDIA driver. Its root volume is named
  `k8s_base_node_instance_sbs_volume_0`, which says what Scaleway built it for.
- Another nobody wrote down, answered by the second `make up`: **the L4 quota is
  zero until the Organization's identity is verified.** Blocked on the account, not
  the code. See [Prerequisites](prerequisites.md).
- ~~Whether Scaleway's Private Network DHCP configures a NIC attached after boot
  without the netplan fallback in `common.sh.tftpl` having to fire.~~
  **Answered: DHCP delivered it, the static fallback never ran.**

- ~~Which exact Kubernetes patch version the pinned minor resolves to.~~
  **Answered: `1.36.4-1.1`**, now pinned in `terraform.tfvars.example`.

## What happened

In two parts. On 2026-09-22 the control plane and the GitOps layer came up, and most
of the open questions were answered with no GPU ever rented. On 2026-09-24 the GPU
node was created, joined, given its driver by the GPU Operator, passed the
acceptance test and was destroyed again, in one 0.39 hour session.

### Control plane and GitOps bootstrap

Status: **done**.

`make cluster` provisioned the Private Network and the control plane node and
returned a working kubeconfig. `make argocd` installed ArgoCD and applied the app of
apps.

```{ .sh .terminal }
$ kubectl get nodes -o wide
NAME              STATUS   ROLES           AGE   VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION               CONTAINER-RUNTIME
gpu-fleet-cp-01   Ready    control-plane   35m   v1.36.4   172.16.32.10   <none>        Ubuntu 22.04.5 LTS   5.15.0-190-generic (amd64)   containerd://2.3.5
```

`INTERNAL-IP` is `172.16.32.10`, which is the address booked in IPAM by
`terraform/network.tf` before the node existed. The kubelet is advertising the
address the API server certificate was issued for and the address the GPU node will
later join through, because all three are the same variable.

The private NIC is attached by Terraform as a separate resource, so it appears after
the instance has booted. The bootstrap waits for a non primary interface to show up,
writes it a netplan stanza asking for DHCP, and only falls back to configuring the
reserved address statically if DHCP has not produced it within a minute. On this
node the first path was enough:

```{ .sh .terminal }
$ ssh root@cp-01 "grep -E 'DHCP|statically' /var/log/gpu-fleet-bootstrap.log"
[bootstrap 2026-09-22T13:41:58+00:00] DHCP gave ens6 the reserved address 172.16.32.10
```

Two things in one line. Scaleway's VPC DHCP does hand out the IPAM reservation to a
NIC attached after boot, so the static fallback is insurance rather than the main
path. And the interface came up as `ens6`, which is why the script detects it by
elimination rather than naming it: the number depends on how many NICs the instance
already had, so hardcoding it would work on the control plane and break on a GPU
node with a different device layout.

What this does not prove is that the netplan stanza was necessary. The bootstrap
writes it before waiting, so it cannot distinguish between Scaleway's image
configuring the interface on its own and our configuration doing it. That question
is not worth an experiment, because the fallback has to exist either way.

Each node writes what its bootstrap actually installed to
`/var/lib/gpu-fleet/bootstrap-facts.txt`, which is where these numbers come from
rather than from anyone's recollection of what was pinned:

```{ .sh .terminal }
$ ssh root@cp-01 cat /var/lib/gpu-fleet/bootstrap-facts.txt
node_name=gpu-fleet-cp-01
node_ip=172.16.32.10
os=Ubuntu 22.04.5 LTS
kernel=5.15.0-190-generic
containerd=containerd containerd v2.3.5 1294c24a7da8e5a793ed378161673abe94118892
kubeadm=v1.36.4
kubelet_package=1.36.4-1.1
bootstrapped_at=2026-09-22T13:42:30+00:00
```

`kubelet_package=1.36.4-1.1` is the answer to the last open question, and it is now
`kubernetes_package_version` in `terraform.tfvars.example`. Before this the
repository pinned a minor and took whatever patch apt served that day, which makes a
rebuild similar rather than identical. Now it is identical.

The containerd version is worth a second look. `containerd.io` from the Docker
repository is on the 2.x series, which uses config schema version 3, where the
runtime options moved to `[plugins.'io.containerd.cri.v1.runtime'...]`. The
bootstrap sets the cgroup driver with a blanket substitution on
`SystemdCgroup = false`, which survives that move because the key name did not
change. The node reaching Ready is the proof it landed: a wrong cgroup driver does
not fail loudly, it produces a kubelet that starts and then misbehaves under
memory pressure.

### Both Applications resolve and sync, with no GPU in the cluster

Status: **done**.

ArgoCD pulls and renders a chart whether or not there is a node to put it on, so the
riskiest unknown in the whole session was answerable before spending anything on a
GPU:

```{ .sh .terminal }
$ kubectl -n argocd get applications.argoproj.io
NAME                     SYNC STATUS   HEALTH STATUS
gpu-operator             Synced        Healthy
node-feature-discovery   Synced        Healthy
root                     Synced        Healthy
```

That settles the GPU Operator chart version. NVIDIA's Helm repository serves it as
`v26.7.0`, with the `v`, which is what `gitops/apps/gpu-operator.yaml` asks for. A
wrong version string would have surfaced here as `ComparisonError: failed to get
chart`, and it would otherwise have surfaced about thirty five minutes into a billed
session.

The capture in
[`session-a-applications.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-a-applications.txt)
was taken a few minutes earlier and shows `root` as `OutOfSync` against revision
`4c61ae3`. That is not a fault, it is the polling interval: commits had landed on
`main` and ArgoCD had not yet noticed. It reconciled itself on the next pass with no
intervention, which is the behaviour `selfHeal` is there to provide. The artifact is
left as captured rather than retaken, because a record that only ever shows the
steady state is not much of a record.

!!! warning "Green here does not mean working"
    `gpu-operator` reports Healthy with zero GPUs in the cluster. Its DaemonSets
    select on a label no node carries yet, so they are satisfied by having nothing to
    schedule. This is worth saying plainly because it is the kind of green that gets
    mistaken for a passing test. The real acceptance test is a CUDA pod, and it has
    not run.

### Node Feature Discovery, sync wave 0

Status: **done**, and it confirms the configuration decision.

```{ .sh .terminal }
$ kubectl -n node-feature-discovery get pods
NAME                                             READY   STATUS    RESTARTS   AGE
node-feature-discovery-gc-7774bfb87f-78lz6       1/1     Running   0          28m
node-feature-discovery-master-7d4f8679f8-g7jdt   1/1     Running   0          28m
node-feature-discovery-worker-6m6p5              1/1     Running   0          28m
```

One line in the label dump is worth more than the rest of it put together:

```{ .sh .terminal }
$ kubectl get nodes --show-labels | tr ',' '\n' | grep feature.node
...
feature.node.kubernetes.io/pci-1af4.present=true
...
```

`1af4` is the virtio vendor ID, from the paravirtual NIC on the control plane. The
label is `pci-<vendor>.present`, with no device class in it, which is the proof that
`deviceLabelFields: [vendor]` took effect. Had the chart default of `[class, vendor]`
been in force, this would read `pci-0200_1af4.present` instead, and by the same
mechanism the GPU node would later come up labelled `pci-0300_10de.present` while
every GPU Operator component sat waiting for `pci-10de.present`. See
[Findings](findings.md) for why that matters and how it was nearly missed.

Checking this against a virtio NIC on a CPU node, rather than against a real GPU,
costs nothing and answers the question a week earlier.

The same dump confirms the node is what Terraform was asked for:

| Label | Value |
|---|---|
| `system-os_release.ID` | `ubuntu` |
| `system-os_release.VERSION_ID` | `22.04` |
| `kernel-version.full` | `5.15.0-190-generic` |
| `cpu-model.vendor_id` | `AMD` |
| `cpu-model.hypervisor` | `kvm` |

No `nvidia.com/*` labels, correctly: GPU Feature Discovery ships inside the GPU
Operator and has no GPU to describe yet.

### Getting an L4 at all

Status: **done**, at the third attempt, with no GPU billed for the first two.

The first `make up` failed on the image: Scaleway does not offer plain Ubuntu on GPU
instance types. The second got past the image and failed on quota: `L4-1-24G` is
zero until the Organization's identity is verified. Both are written up in
[Findings](findings.md), and both cost nothing, because each failed before any
server existed. The third created the node.

### GPU node: what the image brought, and what it did not

Status: **done**.

The bootstrap records the image as it arrived, before changing anything
([`session-a-gpu-image-inventory.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-a-gpu-image-inventory.txt)):

```{ .sh .terminal }
== os
Ubuntu 24.04.4 LTS - 2026-09-09 - df5effdf
6.8.0-136-generic
== binaries
nvidia-smi   absent
containerd   absent
runc         absent
kubelet      absent
kubeadm      absent
kubectl      absent
docker       absent
crictl       absent
== packages
none of interest
== units
none of interest
== kernel modules
nouveau              3096576  0
```

`kapsule_noble` is a bare Ubuntu 24.04. Despite being built for Scaleway's managed
Kubernetes, it arrives with no container runtime and no Kubernetes packages, so
there was nothing for kubeadm to clash with. It also arrives with no NVIDIA driver.
What it does have is `nouveau`, the in-kernel open source driver, loaded and
attached to the L4. Everything NVIDIA on this node from this point on came from the
GPU Operator.

The L4 was visible on the PCI bus from the first boot:

```{ .sh .terminal }
01:00.0 3D controller [0302]: NVIDIA Corporation AD104GL [L4] [10de:27b8] (rev a1)
```

`[0302]` is the 3D controller class and `10de` the NVIDIA vendor ID, which are the
two values the NFD configuration from wave 0 was written to turn into a label.

### Join, label, driver

Status: **done**.

`gpu-up.sh` asked the control plane for a join command with a 30 minute token, ran
it on the node, and the node came up Ready. NFD labelled it exactly as the operator
needed:

```{ .sh .terminal }
$ kubectl get nodes -L feature.node.kubernetes.io/pci-10de.present
NAME               STATUS   ROLES           AGE   VERSION   PCI-10DE.PRESENT
gpu-fleet-cp-01    Ready    control-plane   41h   v1.36.4
gpu-fleet-gpu-01   Ready    <none>          6m2s  v1.36.4   true
```

With that label present, the GPU Operator's DaemonSets finally had a node to match.
The driver container built the pinned driver against the node's own kernel
([`session-a-driver-install.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-a-driver-install.txt)):

```{ .sh .terminal }
Starting installation of NVIDIA driver version 595.91.07 for Linux kernel version 6.8.0-136-generic
Installing Linux kernel headers...
Installing Linux kernel module files...
Done, now waiting for signal
```

The whole operator stack then came up on the GPU node
([`session-a-gpu-operator-pods.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-a-gpu-operator-pods.txt)):

```{ .sh .terminal }
NAME                                       READY   STATUS      RESTARTS      AGE   NODE
gpu-feature-discovery-mvd5b                1/1     Running     0             14m   gpu-fleet-gpu-01
gpu-operator-6cd4764cbf-4t72b              1/1     Running     0             41h   gpu-fleet-cp-01
nvidia-container-toolkit-daemonset-knqhl   1/1     Running     0             14m   gpu-fleet-gpu-01
nvidia-cuda-validator-vfqd6                0/1     Completed   0             12m   gpu-fleet-gpu-01
nvidia-dcgm-exporter-n2wmw                 1/1     Running     3 (11m ago)   14m   gpu-fleet-gpu-01
nvidia-dcgm-qbvcv                          1/1     Running     0             14m   gpu-fleet-gpu-01
nvidia-device-plugin-daemonset-b65gc       1/1     Running     0             14m   gpu-fleet-gpu-01
nvidia-driver-daemonset-wml6j              1/1     Running     0             14m   gpu-fleet-gpu-01
nvidia-operator-validator-jx89f            1/1     Running     0             14m   gpu-fleet-gpu-01
```

The `IP`, `NOMINATED NODE` and `READINESS GATES` columns are left out here for
width. The artifact has them unedited.

Two things in that list are worth more than a glance.

The operator itself is 41 hours old and runs on the control plane. It was deployed
by ArgoCD on 2026-09-22 and sat idle for two days with nothing to manage, then
reacted to a GPU node appearing without anyone touching it. That is the GitOps
claim, observed rather than asserted.

`nvidia-dcgm-exporter` restarted three times in its first few minutes and has been
stable since. The likeliest reading is that it started before DCGM and the driver
were ready and crash looped until they were, but that is a reading, not a finding:
the restart reasons were not captured. DCGM telemetry is the whole of Session B, so
this is left open for it rather than explained away here.

Session B answered it: the exporter starts before the standalone DCGM host engine
accepts connections, exits, and is restarted until it does. The captured log is in
[Session B](02-observability.md#the-exporter-restarts-explained).

What nouveau did during the driver install is not in the captured log lines. What
is established is the before and after: nouveau was loaded and attached to the L4 at
first boot, and afterwards the L4 was served by the NVIDIA driver `595.91.07`.

### GPU Feature Discovery, and the third NFD setting

Status: **done**.

Once the driver was in, GPU Feature Discovery described the GPU in labels
([`session-a-gpu-node.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-a-gpu-node.txt)).
A selection:

| Label | Value |
|---|---|
| `nvidia.com/gpu.product` | `NVIDIA-L4` |
| `nvidia.com/gpu.family` | `ada-lovelace` |
| `nvidia.com/gpu.compute.major` / `.minor` | `8` / `9` |
| `nvidia.com/gpu.memory` | `23034` |
| `nvidia.com/gpu.machine` | `SCW-L4-1-24G` |
| `nvidia.com/cuda.driver-version.full` | `595.91.07` |
| `nvidia.com/cuda.runtime-version.full` | `13.2` |
| `nvidia.com/mig.capable` | `false` |
| `nvidia.com/gpu.sharing-strategy` | `none` |
| `nvidia.com/gpu-driver-upgrade-state` | `upgrade-done` |

That these labels exist at all is the confirmation of the last of the three NFD
settings described in [Findings](findings.md). GPU Feature Discovery publishes into
the `nvidia.com` namespace, which NFD's master refuses unless told otherwise by
`extraLabelNs: [nvidia.com]`. The vendor-only PCI label was proven on a virtio NIC two
days earlier. This proves the rest.

`mig.capable: false` confirms that disabling the MIG manager in
`gitops/values/gpu-operator.yaml` was right for an L4, and `sharing-strategy: none`
is the baseline that time slicing will change in Session D.

### CUDA acceptance test

Status: **passed**.

`make acceptance` checks each criterion from the top of this page and writes what it
saw to `docs/artifacts/` as it goes.

```{ .sh .terminal }
$ make acceptance
...
[Vector addition of 50000 elements]
Copy input data from the host memory to the CUDA device
CUDA kernel launch with 196 blocks of 256 threads
Copy output data from the CUDA device to the host memory
Test PASSED
Done
...
Thu Sep 24 07:45:46 2026
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 595.91.07              Driver Version: 595.91.07      CUDA Version: 13.2     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA L4                      On  |   00000000:01:00.0 Off |                    0 |
| N/A   32C    P8             16W /   72W |       0MiB /  23034MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|  No running processes found                                                             |
+-----------------------------------------------------------------------------------------+

  PASS  node advertises nvidia.com/gpu: 1
  PASS  node carries pci-10de.present=true
  PASS  cuda-vectoradd printed Test PASSED
  PASS  nvidia-smi sees the L4
  PASS  driver in use is 595.91.07, the version pinned in Git
  PASS  image had no NVIDIA driver at first boot (session-a-gpu-image-inventory.txt)

==> acceptance test PASSED. Evidence is in docs/artifacts/session-a-*.txt
```

The fifth line is the one this project exists for. The driver check does not look
for "an NVIDIA driver", it reads the version string out of
`gitops/values/gpu-operator.yaml` and requires `nvidia-smi` to report that exact
string. Read alongside the sixth, it says: this node booted without a driver, and
the driver it is running now is the one a commit asked for.

`CUDA Version: 13.2` is what the driver supports. The test images are CUDA 12.5 and
12.6 on an Ubuntu 22.04 userland, running on a 24.04 host, which is fine: containers
bring their own libraries, and the toolkit injects the host's driver.

### Teardown

Status: **done**.

`make down` cordoned the node, drained it, deleted the node object and destroyed the
instance. The drain had one pod to evict, the completed CUDA validator. Everything
else on the node belonged to a DaemonSet. The warning is one line in the original,
wrapped here for width:

```{ .sh .terminal }
Warning: ignoring DaemonSet-managed Pods: gpu-operator/gpu-feature-discovery-mvd5b,
  gpu-operator/nvidia-container-toolkit-daemonset-knqhl, gpu-operator/nvidia-dcgm-exporter-n2wmw,
  gpu-operator/nvidia-dcgm-qbvcv, gpu-operator/nvidia-device-plugin-daemonset-b65gc,
  gpu-operator/nvidia-driver-daemonset-wml6j, gpu-operator/nvidia-operator-validator-jx89f,
  kube-flannel/kube-flannel-ds-89zgz, kube-system/kube-proxy-ng2dz,
  node-feature-discovery/node-feature-discovery-worker-kpz8m
evicting pod gpu-operator/nvidia-cuda-validator-vfqd6
node/gpu-fleet-gpu-01 drained
```

This was the first live run of the plan guard in `scripts/lib.sh`, which refuses any
GPU apply that would destroy or replace something other than the GPU node. It let
this one through, correctly, because the plan touched nothing else:

```{ .sh .terminal }
Plan: 0 to add, 0 to change, 4 to destroy.
...
scaleway_instance_private_nic.gpu_node[0]: Destruction complete after 5s
scaleway_ipam_ip.gpu_node[0]: Destruction complete after 1s
scaleway_instance_server.gpu_node[0]: Destruction complete after 17s
scaleway_instance_ip.gpu_node[0]: Destruction complete after 1s
```

This is the same cordon, drain and remove path the remediation controller takes in
Session C when a GPU goes bad. It now has one real run behind it.

### What the session cost

| | |
|---|---|
| GPU session opened | 2026-09-24 07:28:16 UTC |
| Acceptance test passed | 2026-09-24 07:45:46 UTC |
| GPU session closed | 2026-09-24 07:51:45 UTC |
| GPU time | 0.39 hours |
| GPU cost at list price | EUR 0.31 |

About 17 and a half minutes from `make up` to a passing acceptance test, including
the human reading the output in between. The two earlier attempts on the same day
failed before any server existed and cost nothing in GPU time. The GPU node's
flexible IP and private IP reservation did exist from the first failed attempt, the
evening before, until this teardown, which costs a fraction of a cent an hour and
is not in the figure above. The control plane bills separately and continuously,
at about EUR 0.04 an hour. Scaleway's console, not this table, is the authority on
what was charged.
