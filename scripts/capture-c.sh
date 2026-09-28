#!/usr/bin/env bash
#
# Capture Session C evidence for one node into docs/artifacts/.
#
#   scripts/capture-c.sh <node> <label>      e.g. gpu-fleet-gpu-01 xid79
#
# Writes session-c-<label>.txt: the node's GPUUnhealthy condition, whether it's
# cordoned, the controller's annotations (millisecond timestamps), the node's
# events, the pods still on it, what the device plugin says about the GPU, and
# the last lines of both the controller's and node-problem-detector's logs.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl jq
require_kubeconfig

NODE="${1:?usage: scripts/capture-c.sh <node> <label>}"
LABEL="${2:?usage: scripts/capture-c.sh <node> <label>}"
OUT="$REPO_ROOT/docs/artifacts/session-c-$LABEL.txt"
mkdir -p "$(dirname "$OUT")"

{
  echo "captured_at=$(date -u +%Y-%m-%dT%H:%M:%SZ) node=$NODE"

  echo "== GPUUnhealthy condition"
  kubectl_cp get node "$NODE" -o json | jq -r '.status.conditions[]? | select(.type=="GPUUnhealthy")
      | "status=\(.status) reason=\(.reason) lastTransitionTime=\(.lastTransitionTime)\nmessage=\(.message)"'

  echo "== scheduling"
  kubectl_cp get node "$NODE" -o json | jq -r '"unschedulable=\(.spec.unschedulable // false)"'

  echo "== controller annotations"
  kubectl_cp get node "$NODE" -o json | jq -r '.metadata.annotations | to_entries[]
      | select(.key | startswith("gpu-fleet.io/")) | "\(.key)=\(.value)"'

  echo "== what the device plugin still advertises"
  kubectl_cp get node "$NODE" -o json | jq -r '"nvidia.com/gpu capacity=\(.status.capacity["nvidia.com/gpu"] // "none") allocatable=\(.status.allocatable["nvidia.com/gpu"] // "none")"'

  echo "== node events"
  kubectl_cp get events -A --field-selector "involvedObject.kind=Node,involvedObject.name=$NODE" \
    --sort-by=.lastTimestamp -o custom-columns='LAST:.lastTimestamp,TYPE:.type,REASON:.reason,SOURCE:.source.component,MESSAGE:.message' \
    | grep -E 'LAST|GPU|Xid|Remediation|Cordon|Drain|Schedul|Classification' || true

  echo "== pods on the node"
  kubectl_cp get pods -A --field-selector "spec.nodeName=$NODE" \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,OWNER:.metadata.ownerReferences[0].kind'

  echo "== the workload"
  kubectl_cp -n gpu-work get pods -o wide 2>/dev/null || echo "no workload namespace"

  echo "== gpu-remediator log, last 20 lines"
  kubectl_cp -n gpu-remediator logs deploy/gpu-remediator --tail=20 2>&1 || true

  echo "== node-problem-detector on $NODE, GPU lines"
  npd="$(kubectl_cp -n kube-system get pods -l app=node-problem-detector --field-selector "spec.nodeName=$NODE" -o jsonpath='{.items[0].metadata.name}')"
  kubectl_cp -n kube-system logs "$npd" 2>&1 | grep -E 'gpu-xid-monitor|GPUUnhealthy|GPUXid' | tail -10 || true

  echo "== timeline so far"
  cat "$REPO_ROOT/docs/artifacts/session-c-timeline.txt" 2>/dev/null || true
} | tee "$OUT"

log "evidence in docs/artifacts/session-c-$LABEL.txt"
