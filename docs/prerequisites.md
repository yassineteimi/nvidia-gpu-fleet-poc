# Prerequisites

## Accounts

- A Scaleway account with API keys, a validated payment method, **and a verified
  identity**. The last one is not optional for this project. Scaleway's quota for
  `L4-1-24G` is zero until the Organization's identity is verified, and one after,
  and the failure only shows up at the moment the GPU node is created:

    ```text
    quota exceeded(s): cp_servers_type_L4_1_24G has reached its quota (0/0)
    ```

    Verification is done once, in the console, from the Organization dashboard, with
    a government photo ID and a camera, and has to be completed within 15 minutes of
    starting. Do it before the first session, not during one. The quota it unlocks is
    one L4 at a time, which is exactly what this project uses, and is why
    `make down` has to finish before the next `make up`.
- A GitHub account. The repository must be public so that ArgoCD can pull it without
  credentials, which is what makes the reproduce path on the landing page real.

## Local tooling

Minimum versions the code in this repository is written against. This table is
replaced with the exact versions actually used once Session A has run.

| Tool | Version | Needed for |
|---|---|---|
| Terraform | 1.9 or newer | Node provisioning |
| kubectl | matching the cluster minor, which is 1.36 | Everything |
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

`.env` holds the Scaleway API keys and the path to your SSH private key. Terraform
never reads a credential from `terraform.tfvars`: the provider takes them from the
environment, which is why every script sources `.env` before doing anything.

### The SSH key

Set `SSH_PRIVATE_KEY_PATH` in `.env` and nothing else. The scripts derive the public
key from it with `ssh-keygen -y` and pass it to Terraform as `TF_VAR_ssh_public_key`,
so the key registered on the nodes is by construction the key you log in with.

The obvious alternative, a public key path in `terraform.tfvars` and a private key
path in `.env`, has one failure mode and it is expensive: set one, forget the other,
and you find out ten minutes into an apply when the SSH wait loop times out against
a node you cannot get into.

ed25519 is the right default on Ubuntu 22.04. An existing RSA key works, and the
scripts will say so on the way past, but a key scoped to this project is tidier:

```{ .sh .terminal }
$ ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_gpu_fleet -C gpu-fleet-poc
```

A passphrase protected key is fine, but `ssh-keygen -y` cannot read it without
prompting, so the scripts fall back to the `.pub` file beside it and say that they
could not verify the two are a pair. Load it into `ssh-agent` before starting a
session or the wait loops will stall on a passphrase prompt.

## Bringing it up

Three commands, in this order. The first two are run once. The last two are the
rhythm of every working session after that.

```{ .sh .terminal }
$ make cluster    # private network and the persistent control plane node
$ make argocd     # install ArgoCD and hand it this repository
$ make up         # create the GPU node, join it, wait for nvidia.com/gpu
$ make down       # drain it, remove it from the cluster, destroy it
```

`make argocd-ui` prints the admin credentials and port-forwards the UI to
`http://localhost:8080`. Plain HTTP, because `server.insecure` is set and the
port-forward is a loopback socket.

!!! note "If the ArgoCD password is rejected"
    Decoding the initial admin secret by hand with `base64 -d` prints a password
    with no trailing newline, so the shell prompt lands flush against the last
    character and you copy the prompt with it. `make argocd-ui` prints it on a
    line of its own. If the password is genuinely wrong, the initial secret is
    stale: ArgoCD leaves it in place after the admin password changes, and a
    repeated `helm upgrade` can regenerate the hash without touching it. The
    script compares the two timestamps and says so when that has happened.

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
