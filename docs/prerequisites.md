# Prerequisites

## Accounts

- **A Scaleway account** with API keys, a validated payment method, **and a verified
  identity**. You can't skip the last one: the `L4-1-24G` quota is zero until the
  Organization's identity is verified, and one afterwards. You only find out when the
  GPU node gets created:

    ```text
    quota exceeded(s): cp_servers_type_L4_1_24G has reached its quota (0/0)
    ```

    You verify once, in the console, from the Organization dashboard, with a
    government photo ID and a camera, and you have 15 minutes to finish once you
    start. Do it before your first session. The quota it unlocks is one L4 at a time,
    which is all this project uses, and it's why `make down` has to finish before the
    next `make up`.
- **A GitHub account.** The repository has to be public so ArgoCD can pull it without
  credentials; that's what makes the reproduce path on the landing page work.

## Local tooling

The minimum versions the code is written against:

| Tool | Version | Needed for |
|---|---|---|
| Terraform | 1.9 or newer | Node provisioning |
| kubectl | matching the cluster minor, 1.36 | Everything |
| helm | 3.14 or newer | ArgoCD bootstrap only |
| shellcheck | any | `make shellcheck` before committing |
| gh | any | Repo and Pages setup |
| docker | with buildx | Building the remediation controller image (Session C) |
| python3 | 3.11 or newer | Controller tests and goodput analysis |

To check them all at once:

```{ .sh .terminal }
$ for t in terraform kubectl helm shellcheck gh docker python3; do printf "%-12s" "$t"; command -v $t >/dev/null && echo ok || echo MISSING; done
```

!!! warning "Apple Silicon"
    Build the remediation controller image for `linux/amd64`. On an ARM Mac, a plain
    `docker build` produces an arm64 image that fails on the node with
    `exec format error`. Use `docker buildx build --platform linux/amd64`.

## Credentials

Copy the templates and fill them in. `.env` is gitignored; never commit it.

```{ .sh .terminal }
$ cp .env.example .env
$ $EDITOR .env
$ cp terraform/terraform.tfvars.example terraform/terraform.tfvars
$ $EDITOR terraform/terraform.tfvars
```

`.env` holds the Scaleway API keys and the path to your SSH private key. Terraform
never reads credentials from `terraform.tfvars`; the provider takes them from the
environment, which is why every script sources `.env` first.

### The SSH key

Set `SSH_PRIVATE_KEY_PATH` in `.env` and nothing else. The scripts derive the public
key with `ssh-keygen -y` and pass it to Terraform as `TF_VAR_ssh_public_key`, so the
key registered on the nodes is always the one you log in with.

The usual alternative, a public key path in `terraform.tfvars` and a private key path
in `.env`, fails in one expensive way. Set one, forget the other, and you find out ten
minutes into an apply, when the SSH wait loop times out against a node you can't get
into.

ed25519 is the right default on Ubuntu 22.04. An existing RSA key works (the scripts
mention it as they go), but a key just for this project is tidier:

```{ .sh .terminal }
$ ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_gpu_fleet -C gpu-fleet-poc
```

A passphrase-protected key works too, but `ssh-keygen -y` can't read it without
prompting, so the scripts fall back to the `.pub` file next to it and warn that they
couldn't check the two match. Load the key into `ssh-agent` before a session, or the
wait loops will stall on a passphrase prompt.

## Bringing it up

`make cluster` and `make argocd` run once. `make up` and `make down` are the start and
end of every session after that.

```{ .sh .terminal }
$ make cluster    # private network and the persistent control plane node
$ make argocd     # install ArgoCD and hand it this repository
$ make up         # create the GPU node, join it, wait for nvidia.com/gpu
$ make down       # drain it, remove it from the cluster, destroy it
```

`make argocd-ui` prints the admin credentials and port-forwards the UI to
`http://localhost:8080`. It's plain HTTP, because `server.insecure` is set and the
port-forward is a loopback socket.

!!! note "If ArgoCD rejects the password"
    Decoding the initial admin secret by hand with `base64 -d` prints the password
    without a trailing newline, so the shell prompt starts right after the last
    character and you copy part of the prompt with it. `make argocd-ui` prints it on
    its own line. If the password really is wrong, the initial secret is stale:
    ArgoCD leaves it in place after the admin password changes, and a repeat
    `helm upgrade` can regenerate the hash without touching it. The script compares
    the two timestamps and tells you when that's happened.

!!! danger "Always run make down"
    `make up` starts an hourly meter, and `make down` is the only thing that stops
    it. `make cost` tells you whether one is running.

## Cost

The GPU node is rented by the hour and destroyed at the end of every session. The
small control plane stays up so Prometheus history survives between sessions.

| Item | Rate | Note |
|---|---|---|
| L4-1-24G GPU node | EUR 0.79/h | Only up during a session |
| Control plane, 4 vCPU / 8 GB | about EUR 0.04/h | About EUR 29/month if left running |
| Block storage and public IPs | a few EUR/month | |

`make cost` shows how long the GPU node has been up in the current session.
