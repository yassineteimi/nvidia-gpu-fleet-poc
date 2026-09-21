# Prerequisites

## Accounts

- A Scaleway account with API keys. GPU instances in `fr-par-2` need no quota
  request in practice, but check L4 stock before booking a session rather than at
  the start of one.
- A GitHub account. The repository must be public so that ArgoCD can pull it without
  credentials, which is what makes the reproduce path on the landing page real.

## Local tooling

Versions below are what this PoC was built and verified with.

| Tool | Version used | Needed for |
|---|---|---|
| Terraform | 1.9.8 | Node provisioning |
| kubectl | 1.31.2 | Everything |
| helm | 4.2.2 | ArgoCD bootstrap only |
| gh | 2.93.0 | Repo and Pages setup |
| docker | with buildx | Building the remediation controller image (Session C) |
| python3 | 3.14 | Controller tests and goodput analysis |

Check them in one go:

```{ .sh .terminal }
$ for t in terraform kubectl helm gh docker python3; do printf "%-12s" "$t"; command -v $t >/dev/null && echo ok || echo MISSING; done
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
```

## Cost

The GPU node is rented hourly and destroyed at the end of every session. The control
plane node is small and stays up so that Prometheus history survives between sessions.

| Item | Rate | Note |
|---|---|---|
| L4-1-24G GPU node | EUR 0.79/h | Only up while a session is running |
| Control plane, 4 vCPU / 8 GB | about EUR 0.04/h | About EUR 29/month if left running |
| Block storage and public IPs | a few EUR/month | |

`make cost` prints how long the GPU node has been up in the current session.
