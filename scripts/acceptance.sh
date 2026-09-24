#!/usr/bin/env bash
#
# Session A acceptance test, run against the live cluster, with the evidence
# written to docs/artifacts/ as it is produced.
#
# The criteria, from docs/01-platform.md:
#   1. a cuda-vectoradd pod reaches Completed with "Test PASSED"
#   2. nvidia-smi inside a CUDA container shows the L4 and the pinned driver
#   3. the node advertises nvidia.com/gpu: 1
#   4. the node carries feature.node.kubernetes.io/pci-10de.present=true
#   5. no GPU software was installed by hand, which is what
#      session-a-gpu-image-inventory.txt records about the image at first boot
#
# The two pods run one after the other, because there is one GPU and nothing
# shares it yet. Time slicing is Session D.
#
# The pods are test fixtures, not platform, so they are applied directly and
# deleted at the end rather than committed to gitops/. The cluster is left in
# the state ArgoCD put it in.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl grep
require_kubeconfig

NS="gpu-acceptance"
OUT="$REPO_ROOT/docs/artifacts"
MANIFESTS="$REPO_ROOT/workloads/acceptance"
GPU_NODE="$(tf_output gpu_node_name)"
GPU_NODE="${GPU_NODE:-gpu-fleet-gpu-01}"
PINNED_DRIVER="$(grep -E '^\s+version: "' "$REPO_ROOT/gitops/values/gpu-operator.yaml" | head -n1 | sed -E 's/.*"(.*)".*/\1/')"

mkdir -p "$OUT"
results=()
record() { results+=("$1"); }

log "GPU node: $GPU_NODE, pinned driver in Git: $PINNED_DRIVER"

########################################
# Evidence about the platform, before running anything on it
########################################

log "capturing GPU Operator state"
kubectl_cp -n gpu-operator get pods -o wide | tee "$OUT/session-a-gpu-operator-pods.txt"

log "capturing the GPU node's resources and GPU labels"
{
  echo "== allocatable"
  kubectl_cp get node "$GPU_NODE" -o jsonpath='{.status.allocatable}'
  echo
  echo "== GPU labels"
  kubectl_cp get node "$GPU_NODE" -o json \
    | grep -oE '"(feature\.node\.kubernetes\.io/pci-10de\.present|nvidia\.com/[A-Za-z0-9._-]+)": *"[^"]*"' \
    | sort
} | tee "$OUT/session-a-gpu-node.txt"

log "capturing how the driver container dealt with nouveau"
kubectl_cp -n gpu-operator logs -l app=nvidia-driver-daemonset -c nvidia-driver-ctr --tail=-1 2>/dev/null \
  | grep -iE 'nouveau|installing|driver version|done' \
  | tee "$OUT/session-a-driver-install.txt" || warn "no driver container logs found"

gpus="$(kubectl_cp get node "$GPU_NODE" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}')"
if [ "$gpus" = "1" ]; then record "PASS  node advertises nvidia.com/gpu: 1"
else record "FAIL  node advertises nvidia.com/gpu: '${gpus:-none}'"; fi

label="$(kubectl_cp get node "$GPU_NODE" -o jsonpath='{.metadata.labels.feature\.node\.kubernetes\.io/pci-10de\.present}')"
if [ "$label" = "true" ]; then record "PASS  node carries pci-10de.present=true"
else record "FAIL  node pci-10de.present is '${label:-absent}'"; fi

########################################
# The workloads
########################################

kubectl_cp create namespace "$NS" --dry-run=client -o yaml | kubectl_cp apply -f - >/dev/null
kubectl_cp -n "$NS" delete pod cuda-vectoradd nvidia-smi --ignore-not-found --wait >/dev/null

run_pod() {
  local name="$1"
  log "running $name"
  kubectl_cp -n "$NS" apply -f "$MANIFESTS/$name.yaml" >/dev/null
  if ! kubectl_cp -n "$NS" wait "pod/$name" \
      --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s; then
    warn "$name did not succeed. Its state:"
    kubectl_cp -n "$NS" describe pod "$name" | tail -n 25 >&2 || true
  fi
  kubectl_cp -n "$NS" logs "$name" | tee "$OUT/session-a-$name.txt"
}

run_pod cuda-vectoradd
if grep -q "Test PASSED" "$OUT/session-a-cuda-vectoradd.txt"; then
  record "PASS  cuda-vectoradd printed Test PASSED"
else
  record "FAIL  cuda-vectoradd did not print Test PASSED"
fi

run_pod nvidia-smi
if grep -q "L4" "$OUT/session-a-nvidia-smi.txt"; then
  record "PASS  nvidia-smi sees the L4"
else
  record "FAIL  nvidia-smi does not show an L4"
fi
if [ -n "$PINNED_DRIVER" ] && grep -q "$PINNED_DRIVER" "$OUT/session-a-nvidia-smi.txt"; then
  record "PASS  driver in use is $PINNED_DRIVER, the version pinned in Git"
else
  record "FAIL  driver in use is not the pinned $PINNED_DRIVER"
fi

if grep -q "nvidia-smi *absent" "$OUT/session-a-gpu-image-inventory.txt" 2>/dev/null; then
  record "PASS  image had no NVIDIA driver at first boot (session-a-gpu-image-inventory.txt)"
else
  record "WARN  session-a-gpu-image-inventory.txt missing or does not show nvidia-smi absent"
fi

kubectl_cp delete namespace "$NS" --wait=false >/dev/null

########################################
# Verdict
########################################

printf '%s\n' "${results[@]}" > "$OUT/session-a-acceptance.txt"
echo
printf '  %s\n' "${results[@]}"
echo
if grep -q '^FAIL' "$OUT/session-a-acceptance.txt"; then
  die "acceptance test FAILED. Evidence is in docs/artifacts/session-a-*.txt"
fi
log "acceptance test PASSED. Evidence is in docs/artifacts/session-a-*.txt"
