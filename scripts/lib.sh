#!/usr/bin/env bash
#
# Shared helpers. Sourced by every script in this directory, never run directly.
#

set -euo pipefail

# These are consumed by the scripts that source this file, which shellcheck
# cannot see from here.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"
KUBECONFIG_PATH="$REPO_ROOT/kubeconfig"
KNOWN_HOSTS="$REPO_ROOT/.ssh-known-hosts"
# shellcheck disable=SC2034
SESSION_LOG="$REPO_ROOT/.gpu-sessions.csv"
# shellcheck disable=SC2034
GPU_TFVARS="$TF_DIR/gpu.auto.tfvars"

log()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m==>\033[0m %s\n' "$*" >&2; exit 1; }

require_tools() {
  local missing=()
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    die "missing required tools: ${missing[*]}"
  fi
}

# Hourly rates used by cost-report.sh. Override them in .env if Scaleway changes
# its pricing. These are list prices, not an invoice.
set_rates() {
  GPU_HOURLY_EUR="${GPU_HOURLY_EUR:-0.79}"
  CONTROL_PLANE_HOURLY_EUR="${CONTROL_PLANE_HOURLY_EUR:-0.04}"
}

# Reads .env if it is there and says nothing if it is not. For scripts that only
# want the rate overrides and never touch the Scaleway API.
load_env_optional() {
  if [ -f "$REPO_ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091 # path is computed at run time
    source "$REPO_ROOT/.env"
    set +a
  fi
  set_rates
}

# Scaleway credentials and the SSH key paths live in a gitignored .env. Nothing
# in this repository ever reads a credential from anywhere else.
load_env() {
  if [ ! -f "$REPO_ROOT/.env" ]; then
    die ".env not found. Copy .env.example to .env and fill it in."
  fi
  set -a
  # shellcheck disable=SC1091 # path is computed at run time
  source "$REPO_ROOT/.env"
  set +a
  set_rates

  : "${SCW_ACCESS_KEY:?SCW_ACCESS_KEY is not set in .env}"
  : "${SCW_SECRET_KEY:?SCW_SECRET_KEY is not set in .env}"
  : "${SCW_DEFAULT_PROJECT_ID:?SCW_DEFAULT_PROJECT_ID is not set in .env}"

  resolve_ssh_keypair
}

# One keypair, one setting.
#
# The public key is derived from the private key and handed to Terraform as
# TF_VAR_ssh_public_key, so the key registered on the nodes is by construction
# the key used to log in to them. The alternative, a public key path in
# terraform.tfvars and a private key path in .env, invites setting one and
# forgetting the other, and you find out ten minutes into an apply when the
# SSH wait loop times out against a node you cannot get into.
resolve_ssh_keypair() {
  SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH:-$HOME/.ssh/id_ed25519}"
  SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH/#\~/$HOME}"

  if [ ! -f "$SSH_PRIVATE_KEY_PATH" ]; then
    warn "no SSH private key at $SSH_PRIVATE_KEY_PATH"
    warn "generate one with:"
    warn "  ssh-keygen -t ed25519 -f $SSH_PRIVATE_KEY_PATH -C gpu-fleet-poc"
    die "set SSH_PRIVATE_KEY_PATH in .env to point at an existing key"
  fi

  # -P "" supplies an empty passphrase, so an encrypted key fails here instead
  # of hanging on an interactive prompt inside a script.
  local derived
  derived="$(ssh-keygen -y -P "" -f "$SSH_PRIVATE_KEY_PATH" 2>/dev/null || true)"

  if [ -n "$derived" ]; then
    SSH_PUBLIC_KEY="$derived"
  elif [ -f "$SSH_PRIVATE_KEY_PATH.pub" ]; then
    warn "$SSH_PRIVATE_KEY_PATH appears to be passphrase protected"
    warn "using $SSH_PRIVATE_KEY_PATH.pub without being able to prove the two are a pair"
    SSH_PUBLIC_KEY="$(cat "$SSH_PRIVATE_KEY_PATH.pub")"
  else
    die "could not derive a public key from $SSH_PRIVATE_KEY_PATH and there is no .pub beside it"
  fi

  # ssh-keygen -y prints two fields and no comment. Scaleway is happier with a
  # third, and it makes the key recognisable in the console.
  case "$SSH_PUBLIC_KEY" in
    *" "*" "*) : ;;
    *) SSH_PUBLIC_KEY="$SSH_PUBLIC_KEY gpu-fleet-poc" ;;
  esac

  case "$SSH_PUBLIC_KEY" in
    "ssh-rsa "*)
      warn "$SSH_PRIVATE_KEY_PATH is an RSA key. Ubuntu 22.04 negotiates rsa-sha2-256 or"
      warn "rsa-sha2-512 with a current client, so this works, but ed25519 is the better"
      warn "default for a cluster you rebuild every week:"
      warn "  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_gpu_fleet -C gpu-fleet-poc"
      ;;
  esac

  export TF_VAR_ssh_public_key="$SSH_PUBLIC_KEY"
}

tf() {
  terraform -chdir="$TF_DIR" "$@"
}

# Apply only when the plan leaves everything except the GPU node alone.
#
# gpu-up and gpu-down apply the whole configuration, not a target, so a plan
# that wanted to replace the control plane would go through unprompted and take
# etcd with it. The realistic trigger is Scaleway publishing a newer ubuntu_jammy
# image between sessions. This saves the plan, refuses it if anything outside the
# GPU node would be destroyed or replaced, and applies exactly the plan that was
# checked, so nothing can change between the check and the apply.
apply_gpu_only() {
  local plan="$TF_DIR/gpu.tfplan"
  local unsafe

  tf plan -input=false -out="$plan"

  unsafe="$(terraform -chdir="$TF_DIR" show -no-color "$plan" \
    | grep -E '# .* (will be destroyed|must be replaced)' \
    | grep -v 'gpu_node' || true)"

  if [ -n "$unsafe" ]; then
    rm -f "$plan"
    warn "the plan would destroy or replace something that is not the GPU node:"
    printf '    %s\n' "$unsafe" >&2
    die "refusing to apply. Run terraform plan in terraform/ and read it before going further."
  fi

  tf apply -input=false "$plan"
  rm -f "$plan"
}

tf_output() {
  terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null || true
}

# StrictHostKeyChecking is left on, against a repository local known_hosts file
# rather than the user's. The GPU node gets a new public IP every session, so
# its entry is removed on the way down instead of host key checking being
# switched off wholesale.
node_ssh() {
  local host="$1"
  shift
  ssh \
    -i "$SSH_PRIVATE_KEY_PATH" \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$KNOWN_HOSTS" \
    -o ConnectTimeout=10 \
    -o LogLevel=ERROR \
    "root@$host" "$@"
}

forget_host() {
  local host="$1"
  [ -f "$KNOWN_HOSTS" ] || return 0
  ssh-keygen -f "$KNOWN_HOSTS" -R "$host" >/dev/null 2>&1 || true
}

wait_for_ssh() {
  local host="$1"
  local timeout="${2:-300}"
  local deadline=$(( $(date +%s) + timeout ))

  log "waiting for SSH on $host"
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if node_ssh "$host" true >/dev/null 2>&1; then
      log "SSH is up on $host"
      return 0
    fi
    sleep 5
  done
  die "SSH did not come up on $host within ${timeout}s"
}

# Both node bootstrap scripts touch this marker as their last action, so its
# presence means cloud-init finished rather than merely started.
wait_for_bootstrap() {
  local host="$1"
  local timeout="${2:-900}"
  local deadline=$(( $(date +%s) + timeout ))

  log "waiting for the bootstrap script on $host to finish"
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if node_ssh "$host" test -f /var/lib/gpu-fleet/bootstrap-complete >/dev/null 2>&1; then
      log "bootstrap complete on $host"
      node_ssh "$host" cat /var/lib/gpu-fleet/bootstrap-facts.txt || true
      return 0
    fi
    sleep 10
  done

  warn "bootstrap did not finish on $host within ${timeout}s. Last 40 lines of its log:"
  node_ssh "$host" tail -n 40 /var/log/gpu-fleet-bootstrap.log || true
  die "bootstrap timed out on $host"
}

kubectl_cp() {
  KUBECONFIG="$KUBECONFIG_PATH" kubectl "$@"
}

require_kubeconfig() {
  [ -f "$KUBECONFIG_PATH" ] \
    || die "no kubeconfig at $KUBECONFIG_PATH. Run scripts/cluster-up.sh first."
}
