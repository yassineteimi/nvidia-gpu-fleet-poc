#!/usr/bin/env bash
#
# Start a working session: create the GPU node, join it to the existing cluster,
# and wait for the GPU to become a schedulable resource.
#
# The join token is never stored anywhere. It is created on the control plane at
# the moment it is needed, with a short lifetime, and the CA is verified through
# the hash the control plane prints alongside it. There is no static token in
# Git and --discovery-token-unsafe-skip-ca-verification is not used.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools terraform kubectl ssh ssh-keygen
load_env
require_kubeconfig

CP_PUBLIC_IP="$(tf_output control_plane_public_ip)"
[ -n "$CP_PUBLIC_IP" ] || die "no control plane in the Terraform state. Run scripts/cluster-up.sh first."

if [ "$(tf_output gpu_node_enabled)" = "true" ]; then
  warn "gpu_node_enabled is already true. Converging rather than creating."
fi

########################################
# Declare the GPU node into existence
#
# The desired state goes into a gitignored tfvars file rather than being passed
# as a one off -target or -var. Terraform then holds the truth about whether a
# GPU is supposed to exist, which means a later plan reports a forgotten node as
# drift instead of agreeing with it.
########################################

SESSION_START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$GPU_TFVARS" <<EOF
# Written by scripts/gpu-up.sh at $SESSION_START. Gitignored.
# scripts/gpu-down.sh sets this back to false.
gpu_node_enabled = true
EOF

log "terraform apply, creating the GPU node"
apply_gpu_only

GPU_PUBLIC_IP="$(tf_output gpu_node_public_ip)"
GPU_NODE_NAME="$(tf_output gpu_node_name)"
[ -n "$GPU_PUBLIC_IP" ] || die "terraform produced no GPU node address"

log "GPU node is $GPU_NODE_NAME at $GPU_PUBLIC_IP"

forget_host "$GPU_PUBLIC_IP"
wait_for_ssh "$GPU_PUBLIC_IP" 600
wait_for_bootstrap "$GPU_PUBLIC_IP" 1800

########################################
# Join
########################################

log "asking the control plane for a fresh join command"
JOIN_COMMAND="$(node_ssh "$CP_PUBLIC_IP" \
  'kubeadm token create --ttl 30m --print-join-command')"

case "$JOIN_COMMAND" in
  "kubeadm join "*--discovery-token-ca-cert-hash*) : ;;
  *) die "the control plane did not return a usable join command" ;;
esac

log "joining $GPU_NODE_NAME to the cluster"
node_ssh "$GPU_PUBLIC_IP" \
  "$JOIN_COMMAND --node-name $GPU_NODE_NAME --cri-socket unix:///run/containerd/containerd.sock"

log "waiting for $GPU_NODE_NAME to report Ready"
kubectl_cp wait --for=condition=Ready "node/$GPU_NODE_NAME" --timeout=600s

kubectl_cp label node "$GPU_NODE_NAME" gpu-fleet.io/role=gpu --overwrite

########################################
# Wait for the GPU Operator to do its job
#
# Nothing here installs a driver. ArgoCD notices the new node, the GPU Operator
# builds or loads the pinned driver, the toolkit patches containerd and the
# device plugin advertises the GPU. This loop just watches for the end of that
# chain. On a cold node it is minutes, not seconds.
########################################

log "waiting for nvidia.com/gpu to be advertised by $GPU_NODE_NAME"
GPU_DEADLINE=$(( $(date +%s) + 1200 ))
GPU_COUNT="0"
while [ "$(date +%s)" -lt "$GPU_DEADLINE" ]; do
  GPU_COUNT="$(kubectl_cp get node "$GPU_NODE_NAME" \
    -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null || true)"
  if [ -n "$GPU_COUNT" ] && [ "$GPU_COUNT" != "0" ]; then
    break
  fi
  sleep 15
done

########################################
# Cost record
########################################

GPU_NODE_TYPE="$(tf_output gpu_node_type)"

if [ ! -f "$SESSION_LOG" ]; then
  echo "started_at,ended_at,node_name,node_type" > "$SESSION_LOG"
fi
echo "$SESSION_START,,$GPU_NODE_NAME,$GPU_NODE_TYPE" >> "$SESSION_LOG"

if [ -n "$GPU_COUNT" ] && [ "$GPU_COUNT" != "0" ]; then
  log "node is advertising nvidia.com/gpu: $GPU_COUNT"
else
  warn "the node is Ready but is not advertising nvidia.com/gpu yet."
  warn "That is expected until the GPU Operator has been synced by ArgoCD. Check:"
  warn "  kubectl -n gpu-operator get pods"
fi

kubectl_cp get nodes -o wide

cat <<EOF

GPU node up since $SESSION_START. It is billing from now until you run:

  make down

EOF
