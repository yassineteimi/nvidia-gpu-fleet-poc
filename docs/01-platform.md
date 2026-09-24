# Session A: platform and GPU lifecycle

!!! success "Done, acceptance passed on 2026-09-24"
    Every criterion passed on a real L4. The node runs NVIDIA driver `595.91.07`, the
    version pinned in Git, which the GPU Operator installed onto an image that had no
    NVIDIA driver at first boot. GPU time for the session: 0.39 hours, EUR 0.31.

**Scope:** Terraform for both nodes, a kubeadm control plane with Flannel, and ArgoCD
managing this repository from the first commit. Node Feature Discovery and the NVIDIA
GPU Operator come from ArgoCD, never from a shell, with driver and container toolkit
versions pinned in Git.

**Acceptance test:** a `cuda-vectoradd` pod completes with `Test PASSED`. `nvidia-smi`
in a CUDA container shows the L4 and the pinned driver. The node advertises
`nvidia.com/gpu: 1` and carries the NFD label
`feature.node.kubernetes.io/pci-10de.present=true`. And nobody installed GPU software
on the node by hand.

## Result

`make acceptance` checks each criterion and writes what it saw to `docs/artifacts/`.

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

The fifth and sixth checks are the reason this project exists. The driver check
doesn't accept any NVIDIA driver: it reads the version string out of
`gitops/values/gpu-operator.yaml` and requires `nvidia-smi` to report exactly that.
Together with the sixth, it means the node booted with no driver, and the driver it's
running now is the one a commit asked for.

`CUDA Version: 13.2` is the highest the driver supports. The test images are CUDA 12.5
and 12.6 on an Ubuntu 22.04 userland, running on a 24.04 host. That's fine, because
containers bring their own libraries and the toolkit injects the host's driver.

## What it cost

| | |
|---|---|
| GPU session opened | 2026-09-24 07:28:16 UTC |
| Acceptance test passed | 2026-09-24 07:45:46 UTC |
| GPU session closed | 2026-09-24 07:51:45 UTC |
| GPU time | 0.39 hours |
| GPU cost at list price | EUR 0.31 |

About 17 and a half minutes from `make up` to a passing acceptance test, including the
time I spent reading output. My two earlier attempts that day failed before any server
existed, so they cost no GPU time. The GPU node's flexible IP and private IP
reservation did exist from the first failed attempt, the evening before, until this
teardown; that's a fraction of a cent an hour and isn't in the figure. The control
plane bills separately, at about EUR 0.04 an hour. Scaleway's console is the authority
on what I was actually charged.

## How the session went

It ran in two parts. On 2026-09-22 I brought up the control plane and the GitOps layer
and answered most of my open questions without renting a GPU. On 2026-09-24 the GPU
node was created, joined, given its driver by the GPU Operator, passed acceptance, and
was destroyed.

### Control plane and ArgoCD

`make cluster` created the Private Network and the control plane and returned a
working kubeconfig. `make argocd` installed ArgoCD and applied the app of apps.

```{ .sh .terminal }
$ kubectl get nodes -o wide
NAME              STATUS   ROLES           AGE   VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION               CONTAINER-RUNTIME
gpu-fleet-cp-01   Ready    control-plane   35m   v1.36.4   172.16.32.10   <none>        Ubuntu 22.04.5 LTS   5.15.0-190-generic (amd64)   containerd://2.3.5
```

`INTERNAL-IP` is `172.16.32.10`, the address `terraform/network.tf` reserved in IPAM
before the node existed. The kubelet advertises the same address the API server
certificate was issued for and the GPU node later joins through, because all three
come from one variable.

Terraform attaches the private NIC as a separate resource, so it shows up after the
instance boots. The bootstrap waits for a non-primary interface, writes it a netplan
stanza asking for DHCP, and only sets the reserved address statically if DHCP hasn't
delivered it within a minute. DHCP was enough:

```{ .sh .terminal }
$ ssh root@cp-01 "grep -E 'DHCP|statically' /var/log/gpu-fleet-bootstrap.log"
[bootstrap 2026-09-22T13:41:58+00:00] DHCP gave ens6 the reserved address 172.16.32.10
```

So Scaleway's VPC DHCP does hand the IPAM reservation to a NIC attached after boot,
and the static path is insurance. The interface came up as `ens6`, which is why the
script finds it by elimination instead of by name: the number depends on how many
NICs the instance already has, and a hardcoded name would work on the control plane
and break on a GPU node with a different device layout.

This doesn't prove my netplan stanza was needed. The bootstrap writes it before
waiting, so I can't tell whether Scaleway's image would have configured the interface
by itself. I didn't test it, since the fallback has to exist either way.

Each node records what its bootstrap actually installed, so the versions below come
from the node rather than from memory:

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

`1.36.4-1.1` is now `kubernetes_package_version` in `terraform.tfvars.example`. Before,
I pinned the minor version and took whatever patch apt served that day, which makes a
rebuild similar rather than identical.

containerd deserves a second look. `containerd.io` from Docker's repository is on 2.x,
which uses config schema version 3, where the runtime options moved to
`[plugins.'io.containerd.cri.v1.runtime'...]`. The bootstrap sets the cgroup driver by
substituting `SystemdCgroup = false`, which still works after the move because the key
name didn't change. A wrong cgroup driver doesn't fail loudly; you get a kubelet that
starts and then misbehaves under memory pressure. The node reaching Ready shows the
setting landed.

### Both Applications sync before any GPU exists

ArgoCD pulls and renders a chart whether or not there's a node to run it on, so I
could settle the riskiest unknown of the session before paying for a GPU:

```{ .sh .terminal }
$ kubectl -n argocd get applications.argoproj.io
NAME                     SYNC STATUS   HEALTH STATUS
gpu-operator             Synced        Healthy
node-feature-discovery   Synced        Healthy
root                     Synced        Healthy
```

NVIDIA's Helm repository serves the GPU Operator chart as `v26.7.0`, with the `v`,
which is what `gitops/apps/gpu-operator.yaml` asks for. A wrong version string would
have shown up here as `ComparisonError: failed to get chart` instead of about 35
minutes into a billed session.

The earlier capture in
[`session-a-applications.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-a-applications.txt)
shows `root` as `OutOfSync` against revision `4c61ae3`. That's the polling interval:
commits had landed on `main` and ArgoCD hadn't picked them up yet. It reconciled on
the next pass without any help. I left the artifact as captured.

!!! warning "Healthy here doesn't mean working"
    `gpu-operator` reports Healthy with no GPU in the cluster. Its DaemonSets select
    on a label no node has yet, so they're satisfied by having nothing to schedule.
    That's easy to mistake for a passing test. The real test is a CUDA pod.

### Node Feature Discovery, checked on a NIC

```{ .sh .terminal }
$ kubectl -n node-feature-discovery get pods
NAME                                             READY   STATUS    RESTARTS   AGE
node-feature-discovery-gc-7774bfb87f-78lz6       1/1     Running   0          28m
node-feature-discovery-master-7d4f8679f8-g7jdt   1/1     Running   0          28m
node-feature-discovery-worker-6m6p5              1/1     Running   0          28m
```

One label in the dump matters more than the rest:

```{ .sh .terminal }
$ kubectl get nodes --show-labels | tr ',' '\n' | grep feature.node
...
feature.node.kubernetes.io/pci-1af4.present=true
...
```

`1af4` is the virtio vendor ID, from the control plane's paravirtual NIC. The label is
`pci-<vendor>.present` with no device class, so `deviceLabelFields: [vendor]` took
effect. With the chart default, `[class, vendor]`, it would read
`pci-0200_1af4.present`, and later the GPU node would have been labelled
`pci-0300_10de.present` while every GPU Operator component waited for
`pci-10de.present`. [Findings](findings.md) explains how close I came to missing this.
Testing it on a virtio NIC cost nothing and gave me the answer a week early.

The same dump confirms the node matches what I asked Terraform for:

| Label | Value |
|---|---|
| `system-os_release.ID` | `ubuntu` |
| `system-os_release.VERSION_ID` | `22.04` |
| `kernel-version.full` | `5.15.0-190-generic` |
| `cpu-model.vendor_id` | `AMD` |
| `cpu-model.hypervisor` | `kvm` |

No `nvidia.com/*` labels yet, as expected: GPU Feature Discovery ships with the GPU
Operator and has no GPU to describe.

### Getting an L4 took three attempts

The first `make up` failed on the image, because Scaleway doesn't offer plain Ubuntu
on GPU instance types. The second failed on quota: `L4-1-24G` is zero until the
Organization's identity is verified. Both failed before any server existed, so neither
cost anything, and both are in [Findings](findings.md). The third attempt created the
node.

### What the image came with

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

Although Scaleway built `kapsule_noble` for its managed Kubernetes, it's a bare Ubuntu
24.04: no container runtime, no Kubernetes packages, nothing for kubeadm to clash with,
and no NVIDIA driver. It does have `nouveau`, the in-kernel open source driver, loaded
and attached to the L4. Everything NVIDIA on the node from here on came from the GPU
Operator.

The L4 was on the PCI bus from first boot:

```{ .sh .terminal }
01:00.0 3D controller [0302]: NVIDIA Corporation AD104GL [L4] [10de:27b8] (rev a1)
```

`[0302]` is the 3D controller class and `10de` is NVIDIA's vendor ID, the two values
my NFD configuration turns into a label.

### Join, label, driver

`gpu-up.sh` got a join command with a 30 minute token from the control plane, ran it
on the node, and the node came up Ready with the label the operator needs:

```{ .sh .terminal }
$ kubectl get nodes -L feature.node.kubernetes.io/pci-10de.present
NAME               STATUS   ROLES           AGE   VERSION   PCI-10DE.PRESENT
gpu-fleet-cp-01    Ready    control-plane   41h   v1.36.4
gpu-fleet-gpu-01   Ready    <none>          6m2s  v1.36.4   true
```

With the label in place, the GPU Operator's DaemonSets had a node to match, and the
driver container built the pinned driver against the node's kernel
([`session-a-driver-install.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-a-driver-install.txt)):

```{ .sh .terminal }
Starting installation of NVIDIA driver version 595.91.07 for Linux kernel version 6.8.0-136-generic
Installing Linux kernel headers...
Installing Linux kernel module files...
Done, now waiting for signal
```

Then the rest of the operator stack came up on the GPU node
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

I cut the `IP`, `NOMINATED NODE` and `READINESS GATES` columns for width; the artifact
has them.

Look at the operator's age: 41 hours, on the control plane. ArgoCD deployed it on
2026-09-22, it sat for two days with nothing to manage, then picked up the new GPU
node without anyone touching it.

`nvidia-dcgm-exporter` restarted three times in its first few minutes. I suspected it
had started before DCGM was ready, but I hadn't captured the restart reasons, so I left
it open. [Session B](02-observability.md#two-restarts-and-an-alert-that-miscounted-them)
confirmed it: the exporter starts before the standalone DCGM host engine accepts
connections, exits, and gets restarted until it does.

The captured log lines don't show what happened to nouveau during the driver install.
What I can show is before and after: nouveau was attached to the L4 at first boot, and
afterwards the NVIDIA driver `595.91.07` served it.

### GPU Feature Discovery

Once the driver was in, GPU Feature Discovery labelled the node
([`session-a-gpu-node.txt`](https://github.com/yassineteimi/nvidia-gpu-fleet-poc/blob/main/docs/artifacts/session-a-gpu-node.txt)).
Some of them:

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

These labels only exist because of the third NFD setting in [Findings](findings.md).
GPU Feature Discovery publishes into the `nvidia.com` namespace, and NFD's master
rejects that unless `extraLabelNs: [nvidia.com]` allows it.

`mig.capable: false` confirms that turning off the MIG manager in
`gitops/values/gpu-operator.yaml` was right for an L4. `sharing-strategy: none` is the
baseline Session D's time slicing will change.

### Teardown

`make down` cordoned the node, drained it, deleted the node object and destroyed the
instance. There was one pod to evict, the completed CUDA validator; everything else
belonged to a DaemonSet. The warning below is one line in the original, wrapped for
width:

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

It was also the first real run of the plan guard in `scripts/lib.sh`, which refuses any
GPU apply that would destroy or replace anything other than the GPU node. The plan
touched nothing else, so the guard let it through:

```{ .sh .terminal }
Plan: 0 to add, 0 to change, 4 to destroy.
...
scaleway_instance_private_nic.gpu_node[0]: Destruction complete after 5s
scaleway_ipam_ip.gpu_node[0]: Destruction complete after 1s
scaleway_instance_server.gpu_node[0]: Destruction complete after 17s
scaleway_instance_ip.gpu_node[0]: Destruction complete after 1s
```

Session C's remediation controller will take the same cordon, drain and remove path
when a GPU goes bad.

## Open questions, and what answered them

| Question going in | Answer |
|---|---|
| Does NVIDIA's Helm repository serve the GPU Operator chart as `v26.7.0` or `26.7.0`? | `v26.7.0`, with the prefix. The Application syncs |
| Does NFD produce `pci-10de.present` or `pci-0300_10de.present`? | The vendor-only form. Confirmed on a virtio NIC before any GPU existed |
| Is `PLAY2-MICRO` offered in `fr-par-2` at 4 vCPU and 8 GB, and what root volume do it and `L4-1-24G` need? | Both run on `sbs_volume`. The L4's root volume came up as 150 GB SBS at 5000 IOPS |
| Does `kapsule_noble` bring Kubernetes components that clash with kubeadm? | No. No container runtime, no Kubernetes packages, no NVIDIA driver. Its root volume is named `k8s_base_node_instance_sbs_volume_0`, which says what Scaleway built it for |
| Does Private Network DHCP configure a NIC attached after boot, without my netplan fallback? | Yes. The static fallback never ran |
| Which Kubernetes patch does the pinned minor resolve to? | `1.36.4-1.1`, now pinned in `terraform.tfvars.example` |
| Not on my list: is plain Ubuntu offered on the L4? | No. The GPU node boots `kapsule_noble` |
| Not on my list either: can I rent an L4 straight away? | No. The quota is zero until the Organization's identity is verified. See [Prerequisites](prerequisites.md) |

## Design decisions

### The GPU node boots a driverless image

Scaleway publishes GPU images with the NVIDIA driver and container toolkit already
installed. Booting one would work, and it would defeat the point of the project,
because the image would own the driver lifecycle instead of the GPU Operator. Two
gates prevent it. Terraform rejects any image label containing `gpu_os`, and the GPU
node's bootstrap exits non-zero if it finds `nvidia-smi`, `/dev/nvidia0` or a loaded
`nvidia` kernel module. The first checks intent and the second checks the result. The
second runs before anything else is installed, since every minute on that node is
billed.

My original plan was plain `ubuntu_jammy`, which Scaleway doesn't offer on GPU instance
types. I used `kapsule_noble` instead, the image Scaleway's managed Kubernetes boots on
GPU pools before its own GPU Operator installs the driver. [Findings](findings.md) has
how I found it.

### Node addresses are reserved in IPAM before the nodes exist

The control plane needs its API server address before it boots: it goes into
`kubeadm init` as the advertise address, into the certificate SANs, and into the join
endpoint the GPU node uses days later. Reserving both private addresses as
`scaleway_ipam_ip` resources makes them known at plan time. Each node tries DHCP first
and only configures the reservation statically if DHCP hasn't delivered it, so both
paths end at the same address.

`node_ip_mode` switches the whole cluster between the Private Network and public
addresses with one variable, as a way out if the Private Network's DHCP misbehaves on
the day.

### Flannel is pinned to an interface

With two interfaces, Flannel picks the one that holds the default route, which is the
public one. Left alone it would build its VXLAN mesh over the internet while the
kubelet advertises a private address. The control plane bootstrap patches the
DaemonSet with `--iface-can-reach` pointing at the control plane address, so pod
traffic takes the same path as everything else.

### The GPU node is a count, not a `-target`

`gpu_node_enabled` defaults to `false`. `gpu-up.sh` writes `gpu_node_enabled = true`
to a gitignored `gpu.auto.tfvars` and applies; `gpu-down.sh` writes `false` and
applies. I avoided `terraform apply -target` on purpose. With a toggle, Terraform knows
whether a GPU is supposed to exist, so a plan on Tuesday reports a node I forgot on
Saturday as drift instead of accepting it. An L4 left running for a week costs more
than this whole PoC's budget.

### Node Feature Discovery is its own Application

The GPU Operator can deploy NFD itself, and most installs let it. I set `nfd.enabled`
to `false` and run NFD in sync wave 0 with its own pinned chart. The operator's node
selectors, scheduling and, from Session C, the remediation controller all depend on
NFD's labels, so I want that configuration in Git where I can read it. The cost is
replicating what the operator's subchart would have configured, which is in
[Findings](findings.md).

### The join token is created on demand

`gpu-up.sh` asks the control plane for
`kubeadm token create --ttl 30m --print-join-command` over SSH and runs the result on
the new node. No bootstrap token is committed or kept in Terraform state, and I don't
use `--discovery-token-unsafe-skip-ca-verification`: the CA hash comes back in the
same printed command.

## What I wrote before the session

I wrote the code ahead of time so the billed session was spent running and watching,
not typing. Before the session, `terraform fmt` and `shellcheck` passed and the
cloud-init templates rendered and passed a syntax check. That's a much weaker claim
than "it works", which only the session could make.

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
