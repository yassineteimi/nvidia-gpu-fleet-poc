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

require_tools terraform kubectl ssh-keygen curl jq
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

########################################
# Check Scaleway itself for anything left behind
#
# Terraform only knows what it created. When an L4 is created but can't be
# booted (no capacity), Scaleway can still create its root volume without
# attaching it: the server's state has no volume ID, the provider fails the
# destroy with "volume ID not found", and a 150 GB volume keeps billing where
# Terraform can't see it. That happened in Session D. So after every teardown,
# successful or not, ask the API what's still in the GPU node's zone: a server
# with its name, and any block volume nothing is attached to. This only
# reports. Deleting by a guess is worse than a warning.
########################################

check_leftovers() {
  local zone region zones api servers volumes found=0
  zone="$(tf_output gpu_zone)"
  [ -n "$zone" ] || zone="$(tf_output zone)"
  # Every zone of the region, not only the GPU zone of the moment: in Session D
  # a failed boot in fr-par-2 left a volume behind, the next attempt moved the
  # GPU zone to fr-par-1, and a check of the GPU zone alone missed it for three
  # days. LEFTOVER_ZONES overrides the list.
  region="${zone%-*}"
  zones="${LEFTOVER_ZONES:-${region:+$region-1 $region-2 $region-3}}"
  [ -n "$zones" ] || { warn "no zone in the Terraform outputs, skipping the leftover check"; return 0; }
  api="https://api.scaleway.com"

  for zone in $zones; do
    servers="$(curl -fsS -H "X-Auth-Token: $SCW_SECRET_KEY" "$api/instance/v1/zones/$zone/servers?name=$GPU_NODE_NAME" 2>/dev/null \
      | jq -r --arg n "$GPU_NODE_NAME" '.servers[] | select(.name == $n) | "\(.id) state=\(.state)"' || true)"
    volumes="$(curl -fsS -H "X-Auth-Token: $SCW_SECRET_KEY" "$api/block/v1alpha1/zones/$zone/volumes" 2>/dev/null \
      | jq -r '.volumes[] | select((.references // []) | length == 0) | "\(.id) \(.name) \(.size / 1e9)GB created=\(.created_at)"' || true)"
    [ -z "$servers" ] && [ -z "$volumes" ] && continue
    found=1
    warn "still at Scaleway in $zone, and billing:"
    [ -n "$servers" ] && printf '    server %s\n' "$servers" >&2
    [ -n "$volumes" ] && printf '    unattached volume %s\n' "$volumes" >&2
    warn "check each one is this node's, then delete it through the API, server first:"
    warn "  curl -X DELETE -H \"X-Auth-Token: \$SCW_SECRET_KEY\" $api/instance/v1/zones/$zone/servers/<id>"
    warn "  curl -X DELETE -H \"X-Auth-Token: \$SCW_SECRET_KEY\" $api/block/v1alpha1/zones/$zone/volumes/<id>"
  done

  if [ "$found" -eq 0 ]; then
    log "Scaleway shows no GPU server and no unattached volume in $zones"
  else
    warn "then, if a server was listed: terraform -chdir=terraform state rm 'scaleway_instance_server.gpu_node[0]' && make down"
  fi
}

log "terraform apply, destroying the GPU node"
trap check_leftovers EXIT
apply_gpu_only

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
