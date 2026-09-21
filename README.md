<h1 align="center">NVIDIA GPU Fleet PoC: Day 2 operations on upstream Kubernetes</h1>

<p align="center">
  <b>Driver lifecycle · GPU health telemetry · Automated fault remediation</b>: taking a GPU node from bare instance to a production-stable, self-healing platform<br/>
  GitOps-first · ArgoCD app-of-apps · declarative everything · reproducible from Git in minutes
</p>

<p align="center">
  <a href="https://yassineteimi.github.io/nvidia-gpu-fleet-poc/"><b>Read the full build and runbook</b></a>
</p>

---

A rented NVIDIA L4 node taken from a bare cloud instance to a GitOps-managed,
monitored, self-remediating GPU platform on upstream Kubernetes, then destroyed and
rebuilt from Git. The driver and container toolkit are never touched by hand: they are
pinned in a values file and rolled by a commit. GPU faults are detected from the kernel
log, surfaced as node conditions, and acted on by a controller that cordons and drains
without a human. Everything runs on one GPU node plus a small control plane, which is
honest about being a scaled-down instance of a fleet method rather than a fleet.

**What is simulated is stated plainly.** The GPU never actually failed. The XID error is
injected as a kernel log line so the detection and remediation path downstream of it can
be exercised for real. The full list is on the
[What is simulated](https://yassineteimi.github.io/nvidia-gpu-fleet-poc/simulated/) page,
and nothing is left off it.

## The four capabilities

| Capability | What it does | Built in |
| --- | --- | --- |
| **Driver and toolkit lifecycle** | NVIDIA GPU Operator with Node Feature Discovery, versions pinned in Git, driver bumps performed as a commit and rolled by ArgoCD | Session A |
| **GPU health telemetry** | DCGM exporter with a custom counter set: SM utilisation, framebuffer, temperature, power, ECC counters, clock event reasons and XID. Prometheus alert rules that page on the signals that matter | Session B |
| **Fault detection and remediation** | node-problem-detector reading `NVRM: Xid` from the kernel log into a node condition, and a Python controller that cordons, records an event, annotates and drains. Return to service is gated on `dcgmi diag`, never automatic | Session C |
| **Goodput and acceptance** | A PyTorch job with checkpointing interrupted mid-training, with total, useful and lost time measured. A burn-in record. A cluster acceptance runbook with exit criteria | Session D |

## Repository layout

```text
nvidia-gpu-fleet-poc/
├── docs/          # the published GitHub Pages site (MkDocs Material)
├── terraform/     # both nodes, cloud-init, private network
├── gitops/        # ArgoCD app-of-apps: Applications, Helm values, manifests
├── controllers/   # gpu-remediator, Python on the Kubernetes client
├── workloads/     # CUDA acceptance pod, PyTorch training job, goodput analysis
└── scripts/       # gpu-up, gpu-down, inject-xid, return-to-service, burn-in
```

## Quick start

> Full verified prerequisites live in the
> [tutorial](https://yassineteimi.github.io/nvidia-gpu-fleet-poc/prerequisites/). In short:

```bash
cp .env.example .env    # add your Scaleway API keys (gitignored)
make cluster            # private network and the persistent control plane node, once
make argocd             # install ArgoCD and hand it this repository, once
make up                 # provision the GPU node, join it, wait for the GPU to be schedulable
make down               # drain, remove and destroy the GPU node
make cost               # how long the GPU has been up and what it has cost
```

## Cost control

The GPU node is rented hourly and destroyed at the end of every session. Only the small
control plane persists, so Prometheus history survives between sessions.

| Item | Rate |
| --- | --- |
| Scaleway L4-1-24G, 1x L4 24 GB | EUR 0.79/h, up only during a session |
| Control plane, 4 vCPU / 8 GB | about EUR 0.04/h |

## Secrets hygiene

All credentials come from a gitignored `.env`. Nothing secret is committed, printed to
logs, or published. The site contains zero secrets. The node join token is created on
demand by the control plane and expires; it is never stored in Git.

## Stack

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![NVIDIA](https://img.shields.io/badge/NVIDIA%20GPU%20Operator-76B900?logo=nvidia&logoColor=white)
![Argo CD](https://img.shields.io/badge/Argo%20CD-EF7B4D?logo=argo&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?logo=grafana&logoColor=white)
![PyTorch](https://img.shields.io/badge/PyTorch-EE4C2C?logo=pytorch&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)
![Scaleway](https://img.shields.io/badge/Scaleway-4F0599?logo=scaleway&logoColor=white)

## Connect

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?logo=linkedin&logoColor=white)](https://linkedin.com/in/yassine-teimi)
[![Email](https://img.shields.io/badge/Email-EA4335?logo=gmail&logoColor=white)](mailto:yteimi@gmail.com)

---
<p align="center"><sub>A reproducible method for operating GPU clusters on upstream Kubernetes. Independent work, not affiliated with or endorsed by any vendor named here.</sub></p>
