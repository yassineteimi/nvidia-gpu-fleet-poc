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

## What happened

To be filled in during Session A with real captured output.
