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

  SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH:-$HOME/.ssh/id_ed25519}"
  SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY_PATH/#\~/$HOME}"
  [ -f "$SSH_PRIVATE_KEY_PATH" ] || die "SSH private key not found at $SSH_PRIVATE_KEY_PATH"
}

tf() {
  terraform -chdir="$TF_DIR" "$@"
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
