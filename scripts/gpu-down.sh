#!/usr/bin/env bash
#
# End a working session: take the GPU node out of the cluster properly, then
# destroy it.
#
# The order matters and it is the same order the remediation controller uses in
# Session C. Cordon so nothing new lands on it, drain so running pods are
# evicted and rescheduled rather than killed with the instance, delete the node
# object so the control plane stops waiting for a kubelet that is never coming
# back, and only then destroy the hardware. Running this twice a session, every
# session, means the remediation path is rehearsed long before it is relied on.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools terraform kubectl ssh-keygen
load_env

GPU_NODE_NAME="$(tf_output gpu_node_name)"
GPU_PUBLIC_IP="$(tf_output gpu_node_public_ip)"

if [ "$(tf_output gpu_node_enabled)" != "true" ]; then
  log "gpu_node_enabled is already false, nothing to tear down"
else
  if [ -f "$KUBECONFIG_PATH" ] && [ -n "$GPU_NODE_NAME" ]; then
    if kubectl_cp get node "$GPU_NODE_NAME" >/dev/null 2>&1; then
      log "cordoning $GPU_NODE_NAME"
      kubectl_cp cordon "$GPU_NODE_NAME" || warn "cordon failed, continuing"

      log "draining $GPU_NODE_NAME"
      kubectl_cp drain "$GPU_NODE_NAME" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --force \
        --timeout=180s || warn "drain did not finish cleanly, continuing"

      log "deleting the node object"
      kubectl_cp delete node "$GPU_NODE_NAME" --wait=false || warn "delete node failed, continuing"
    else
      warn "$GPU_NODE_NAME is not in the cluster, skipping the drain"
    fi
  else
    warn "no kubeconfig or no node name, skipping the drain"
  fi
fi

########################################
# Destroy
########################################

cat > "$GPU_TFVARS" <<EOF
# Written by scripts/gpu-down.sh at $(date -u +%Y-%m-%dT%H:%M:%SZ). Gitignored.
# scripts/gpu-up.sh sets this back to true.
gpu_node_enabled = false
EOF

log "terraform apply, destroying the GPU node"
tf apply -input=false -auto-approve

[ -n "$GPU_PUBLIC_IP" ] && forget_host "$GPU_PUBLIC_IP"

########################################
# Close the cost record
########################################

if [ -f "$SESSION_LOG" ]; then
  ENDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Close the most recent row that has no end time.
  awk -F, -v ended="$ENDED_AT" '
    BEGIN { OFS = FS }
    { rows[NR] = $0; if (NR > 1 && $2 == "") last = NR }
    END {
      for (i = 1; i <= NR; i++) {
        if (i == last) {
          split(rows[i], f, FS)
          f[2] = ended
          print f[1], f[2], f[3], f[4]
        } else {
          print rows[i]
        }
      }
    }
  ' "$SESSION_LOG" > "$SESSION_LOG.tmp" && mv "$SESSION_LOG.tmp" "$SESSION_LOG"
fi

log "GPU node destroyed. Nothing GPU shaped is billing."
"$REPO_ROOT/scripts/cost-report.sh" || true
