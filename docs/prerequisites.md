# Prerequisites

## Accounts

- A Scaleway account with API keys. GPU instances in `fr-par-2` need no quota
  request in practice, but check L4 stock before booking a session rather than at
  the start of one.
- A GitHub account. The repository must be public so that ArgoCD can pull it without
  credentials, which is what makes the reproduce path on the landing page real.

## Local tooling

Minimum versions the code in this repository is written against. This table is
replaced with the exact versions actually used once Session A has run.

| Tool | Version | Needed for |
|---|---|---|
| Terraform | 1.9 or newer | Node provisioning |
| kubectl | matching the cluster minor, currently 1.36 | Everything |
| helm | 3.14 or newer | ArgoCD bootstrap only |
| shellcheck | any | `make shellcheck` before committing |
| gh | any | Repo and Pages setup |
| docker | with buildx | Building the remediation controller image (Session C) |
| python3 | 3.11 or newer | Controller tests and goodput analysis |

Check them in one go:

```{ .sh .terminal }
$ for t in terraform kubectl helm shellcheck gh docker python3; do printf "%-12s" "$t"; command -v $t >/dev/null && echo ok || echo MISSING; done
```

!!! warning "Apple Silicon"
    The remediation controller image must be built for `linux/amd64`. On an ARM Mac
    a plain `docker build` produces an arm64 image that fails on the node with
    `exec format error`. Use `docker buildx build --platform linux/amd64`.

## Credentials

Copy the template and fill it in. `.env` is gitignored and must never be committed.

```{ .sh .terminal }
$ cp .env.example .env
$ $EDITOR .env
$ cp terraform/terraform.tfvars.example terraform/terraform.tfvars
$ $EDITOR terraform/terraform.tfvars
```

`.env` holds the Scaleway API keys and the paths to your SSH keypair. Terraform
never reads a credential from `terraform.tfvars`: the provider takes them from the
environment, which is why every script sources `.env` before doing anything.

## Bringing it up

Three commands, in this order. The first two are run once. The last two are the
rhythm of every working session after that.

```{ .sh .terminal }
$ make cluster    # private network and the persistent control plane node
$ make argocd     # install ArgoCD and hand it this repository
$ make up         # create the GPU node, join it, wait for nvidia.com/gpu
$ make down       # drain it, remove it from the cluster, destroy it
```

!!! danger "make down is not optional"
    `make up` starts an hourly meter and `make down` is the only thing that stops
    it. `make cost` will tell you whether one is running.

## Cost

The GPU node is rented hourly and destroyed at the end of every session. The control
plane node is small and stays up so that Prometheus history survives between sessions.

| Item | Rate | Note |
|---|---|---|
| L4-1-24G GPU node | EUR 0.79/h | Only up while a session is running |
| Control plane, 4 vCPU / 8 GB | about EUR 0.04/h | About EUR 29/month if left running |
| Block storage and public IPs | a few EUR/month | |

`make cost` prints how long the GPU node has been up in the current session.
