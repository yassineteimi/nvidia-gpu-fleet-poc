# Session A: platform and GPU lifecycle

!!! info "Status: not yet run"
    This chapter is written during the session, from output captured live, not
    reconstructed afterwards. Until the session has run, this page states the plan
    and the acceptance test only. Nothing is claimed here that has not happened.

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

### The GPU node boots a plain Ubuntu image

Scaleway publishes GPU OS images with the NVIDIA driver and container toolkit already
installed. Booting one would work, and it would quietly delete the point of this
project: the driver lifecycle would belong to the image rather than to the GPU
Operator. So there are two gates against it. Terraform refuses any image label
containing `gpu_os`, and the GPU node's own bootstrap script exits non zero if it
finds `nvidia-smi`, `/dev/nvidia0` or a loaded `nvidia` kernel module. The first
checks the intent, the second checks the result.

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
- Whether `PLAY2-MICRO` is offered in `fr-par-2` at 4 vCPU and 8 GB, and what the root
  volume type constraint is for it and for `L4-1-24G`. **Half answered**: the control
  plane provisioned with `sbs_volume`, so that half holds. The L4 is untested.
- ~~Whether Scaleway's Private Network DHCP configures a NIC attached after boot
  without the netplan fallback in `common.sh.tftpl` having to fire.~~
  **Answered: DHCP delivered it, the static fallback never ran.**

- ~~Which exact Kubernetes patch version the pinned minor resolves to.~~
  **Answered: `1.36.4-1.1`**, now pinned in `terraform.tfvars.example`.

## What happened

!!! warning "In progress, partial"
    The control plane and ArgoCD are up, and three of the four open questions below
    are closed without a GPU ever having been rented. The GPU node has not been
    provisioned, so everything from the join onward is still unwritten. Sections
    marked "not yet run" are exactly that, and nothing is filled in from memory.

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

### GPU node, join and driver

Status: **not yet run**.

### CUDA acceptance test

Status: **not yet run**.
