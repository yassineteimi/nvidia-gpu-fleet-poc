#!/usr/bin/env bash
#
# Put a remediated GPU node back into service, or refuse to.
#
#   scripts/return-to-service.sh <node>          DIAG_LEVEL=2 by default
#
# The order comes from reading node-problem-detector v1.36.0:
#
#   1. Wait out the GPU monitor's 5 minute lookback since the XID. A restart of
#      node-problem-detector replays kernel log lines newer than that, and
#      would set GPUUnhealthy again.
#   2. dcgmi diag at DIAG_LEVEL must pass on the node's GPU.
#   3. Restart node-problem-detector on the node. That is the only way its
#      condition goes back to False: it re-sends its own view of a permanent
#      condition at least every 5 minutes, so patching the node by hand
#      doesn't last.
#   4. GPUUnhealthy must now read False.
#   5. Uncordon, and remove the controller's annotations.
#
# Any gate that fails stops here, with the node still cordoned.
#
# On a node that isn't a GPU node (the free test on the control plane), there
# is no GPU to diagnose and the controller never cordoned it: steps 1, 3 and 4
# run, to clear the condition, and nothing else.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl jq
require_kubeconfig

NODE="${1:?usage: scripts/return-to-service.sh <node>}"
DIAG_LEVEL="${DIAG_LEVEL:-2}"
LOOKBACK_SECONDS=300
GPU_LABEL="feature.node.kubernetes.io/pci-10de.present"
OUT="$REPO_ROOT/docs/artifacts"
TIMELINE="$OUT/session-c-timeline.txt"
mkdir -p "$OUT"

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
node_json() { kubectl_cp get node "$NODE" -o json; }
condition() { node_json | jq -r '.status.conditions[]? | select(.type=="GPUUnhealthy") | "\(.status) \(.lastTransitionTime)"'; }

is_gpu="$(node_json | jq -r --arg l "$GPU_LABEL" '.metadata.labels[$l] // "false"')"
read -r status since <<<"$(condition)"
[ -n "${status:-}" ] || die "$NODE has no GPUUnhealthy condition. Is node-problem-detector running there?"
log "$NODE: GPUUnhealthy=$status since $since, GPU node: $is_gpu"

# 1. The lookback.
if [ "$status" = "True" ]; then
  elapsed=$(( $(date -u +%s) - $(date -u -d "$since" +%s 2>/dev/null || date -u -j -f %Y-%m-%dT%H:%M:%SZ "$since" +%s) ))
  if [ "$elapsed" -lt "$LOOKBACK_SECONDS" ]; then
    die "REFUSED: the XID was logged ${elapsed}s ago. Wait $(( LOOKBACK_SECONDS - elapsed + 5 ))s more, or restarting node-problem-detector will replay it."
  fi
fi

# 2. The diagnostic, on GPU nodes only.
if [ "$is_gpu" = "true" ]; then
  dcgm_pod="$(kubectl_cp -n gpu-operator get pods -l app=nvidia-dcgm --field-selector "spec.nodeName=$NODE" -o jsonpath='{.items[0].metadata.name}')"
  [ -n "$dcgm_pod" ] || die "REFUSED: no nvidia-dcgm pod on $NODE to run the diagnostic with"
  log "running dcgmi diag -r $DIAG_LEVEL in $dcgm_pod, which can take several minutes"
  started="$(stamp)"
  set +e
  kubectl_cp -n gpu-operator exec "$dcgm_pod" -- dcgmi diag -r "$DIAG_LEVEL" 2>&1 | tee "$OUT/session-c-dcgmi-diag.txt"
  rc="${PIPESTATUS[0]}"
  set -e
  echo "diag_level=$DIAG_LEVEL started=$started finished=$(stamp) exit=$rc node=$NODE" | tee -a "$TIMELINE"
  if [ "$rc" -ne 0 ] || grep -qw "Fail" "$OUT/session-c-dcgmi-diag.txt"; then
    die "REFUSED: dcgmi diag -r $DIAG_LEVEL did not pass. $NODE stays cordoned."
  fi
  log "dcgmi diag -r $DIAG_LEVEL passed"
fi

# 3. Restart node-problem-detector on this node.
old="$(kubectl_cp -n kube-system get pods -l app=node-problem-detector --field-selector "spec.nodeName=$NODE" -o jsonpath='{.items[0].metadata.name}')"
[ -n "$old" ] || die "no node-problem-detector pod on $NODE"
log "restarting node-problem-detector ($old) so its GPUUnhealthy condition resets"
kubectl_cp -n kube-system delete pod "$old" --wait=true >/dev/null
deadline=$(( $(date +%s) + 120 ))
until kubectl_cp -n kube-system wait pod -l app=node-problem-detector --field-selector "spec.nodeName=$NODE" \
        --for=condition=Ready --timeout=10s >/dev/null 2>&1; do
  [ "$(date +%s)" -lt "$deadline" ] || die "node-problem-detector did not come back on $NODE. $NODE stays cordoned."
done

# 4. The condition must have cleared, and must stay clear past a replay.
deadline=$(( $(date +%s) + 90 ))
while :; do
  read -r status _ <<<"$(condition)"
  [ "$status" = "False" ] && break
  [ "$(date +%s)" -lt "$deadline" ] || die "REFUSED: GPUUnhealthy is still $status after the restart. Another XID? $NODE stays cordoned."
  sleep 5
done
log "GPUUnhealthy=False on $NODE"

# 5. Back into service.
if [ "$is_gpu" = "true" ]; then
  kubectl_cp uncordon "$NODE"
fi
kubectl_cp annotate node "$NODE" \
  gpu-fleet.io/xid- gpu-fleet.io/xid-logged-at- gpu-fleet.io/cordoned-at- \
  gpu-fleet.io/drained-at- gpu-fleet.io/refused-at- >/dev/null
echo "returned_to_service=$(stamp) node=$NODE gpu_node=$is_gpu diag_level=$DIAG_LEVEL" | tee -a "$TIMELINE"
