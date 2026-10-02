#!/usr/bin/env bash
#
# Handover check: the read-only part of the acceptance runbook, run against a
# GPU node that has just joined. Nothing here changes the cluster.
#
#   scripts/handover.sh [label]      default label: handover
#
# Writes docs/artifacts/session-d-<label>.txt and a PASS/FAIL/CHECK verdict
# beside it. It covers runbook checks 2 to 5, 7 and 11: the node, the GPU's
# enumeration and PCIe link, the driver and toolkit against the versions pinned
# in Git, the ECC and row remapping history the card arrived with, and whether
# its telemetry reaches Prometheus.
#
# ECC history is read twice on purpose: from nvidia-smi on the node, which is
# what an engineer would look at, and from the DCGM counters in Prometheus,
# whose names don't change between driver versions. The verdict on errors uses
# the counters. nvidia-smi's text layout is only parsed for the row remapper's
# Pending and Failure lines, and a layout it doesn't recognise is a CHECK, not
# a PASS.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl jq
require_kubeconfig

LABEL="${1:-handover}"
OUT="$REPO_ROOT/docs/artifacts"
FILE="$OUT/session-d-$LABEL.txt"
VALUES="$REPO_ROOT/gitops/values/gpu-operator.yaml"
PROM="/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy"
mkdir -p "$OUT"

enc() { jq -rn --arg q "$1" '$q|@uri'; }
prom() { kubectl_cp get --raw "$PROM/api/v1/query?query=$(enc "$1")" | jq -r '.data.result[0].value[1] // "no data"'; }

node="$(kubectl_cp get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.name}')"
[ -n "$node" ] || die "no GPU node in the cluster"
pinned_driver="$(awk '/^driver:/{d=1} d && /version:/{gsub(/"/,"",$2); print $2; exit}' "$VALUES")"
pinned_toolkit="$(awk '/^toolkit:/{t=1} t && /version:/{gsub(/"/,"",$2); print $2; exit}' "$VALUES")"
drv="$(kubectl_cp -n gpu-operator get pods -l app=nvidia-driver-daemonset --field-selector "spec.nodeName=$node" -o jsonpath='{.items[0].metadata.name}')"
smi() { kubectl_cp -n gpu-operator exec "$drv" -c nvidia-driver-ctr -- nvidia-smi "$@" 2>&1; }

node_json="$(kubectl_cp get node "$node" -o json)"
label() { jq -r --arg k "$1" '.metadata.labels[$k] // "absent"' <<<"$node_json"; }

{
  echo "captured_at=$(date -u +%Y-%m-%dT%H:%M:%SZ) node=$node"
  echo "== 2. node"
  jq -r '"ready=\(.status.conditions[] | select(.type=="Ready") | .status) kubelet=\(.status.nodeInfo.kubeletVersion) os=\(.status.nodeInfo.osImage) kernel=\(.status.nodeInfo.kernelVersion) runtime=\(.status.nodeInfo.containerRuntimeVersion)"' <<<"$node_json"
  echo "== 3. enumeration and PCIe"
  echo "gpu.count=$(label nvidia.com/gpu.count) gpu.product=$(label nvidia.com/gpu.product) gpu.memory=$(label nvidia.com/gpu.memory)"
  smi --query-gpu=index,name,uuid,serial,pci.bus_id,vbios_version,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max --format=csv
  echo "== 4. Node Feature Discovery"
  echo "feature.node.kubernetes.io/pci-10de.present=$(label feature.node.kubernetes.io/pci-10de.present)"
  echo "== 5. driver and toolkit"
  echo "pinned_driver=$pinned_driver node_driver=$(label nvidia.com/cuda.driver-version.full)"
  echo "pinned_toolkit=$pinned_toolkit toolkit_image=$(kubectl_cp -n gpu-operator get pods -l app=nvidia-container-toolkit-daemonset --field-selector "spec.nodeName=$node" -o jsonpath='{.items[0].spec.containers[0].image}')"
  echo "== 7. ECC and row remapping, from nvidia-smi"
  smi -q -d ECC,ROW_REMAPPER
  echo "== 7. ECC and row remapping, from the DCGM counters in Prometheus"
  for m in DCGM_FI_DEV_ECC_SBE_AGG_TOTAL DCGM_FI_DEV_ECC_DBE_AGG_TOTAL DCGM_FI_DEV_ECC_SBE_VOL_TOTAL DCGM_FI_DEV_ECC_DBE_VOL_TOTAL \
           DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS DCGM_FI_DEV_ROW_REMAP_FAILURE \
           DCGM_FI_DEV_PCIE_REPLAY_COUNTER DCGM_FI_DEV_XID_ERRORS; do
    echo "$m=$(prom "max($m)")"
  done
  echo "== 11. telemetry"
  echo "dcgm_exporter_up=$(prom 'max(up{namespace="gpu-operator", service="nvidia-dcgm-exporter"})')"
} | tee "$FILE"

f="$FILE"
v() { grep -m1 "^$1=" "$f" | cut -d= -f2-; }
results=()
pass() { results+=("PASS  $*"); }
fail() { results+=("FAIL  $*"); }
check() { results+=("CHECK $*"); }

grep -q '^ready=True' "$f" && pass "node Ready" || fail "node not Ready"
[ "$(label nvidia.com/gpu.count)" -ge 1 ] 2>/dev/null && pass "GPU enumerated: $(label nvidia.com/gpu.count) x $(label nvidia.com/gpu.product)" || fail "no GPU enumerated"
[ "$(label feature.node.kubernetes.io/pci-10de.present)" = "true" ] && pass "NFD sees PCI vendor 10de" || fail "NFD label pci-10de.present missing"
[ "$(label nvidia.com/cuda.driver-version.full)" = "$pinned_driver" ] && pass "driver $pinned_driver matches Git" || fail "driver $(label nvidia.com/cuda.driver-version.full), Git pins $pinned_driver"
grep -q "toolkit_image=.*:$pinned_toolkit" "$f" && pass "container toolkit $pinned_toolkit matches Git" || fail "container toolkit image doesn't match $pinned_toolkit"
for m in DCGM_FI_DEV_ECC_DBE_AGG_TOTAL DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS DCGM_FI_DEV_ROW_REMAP_FAILURE; do
  case "$(v "$m")" in
    0) pass "$m is 0" ;;
    "no data") check "$m has no data" ;;
    *) fail "$m is $(v "$m")" ;;
  esac
done
if grep -Eq '^\s*Pending\s*:\s*No' "$f" && grep -Eq '^\s*Remapping Failure Occurred\s*:\s*No' "$f"; then
  pass "row remapper: nothing pending, no failure"
elif grep -Eq '^\s*Pending\s*:\s*Yes|^\s*Remapping Failure Occurred\s*:\s*Yes' "$f"; then
  fail "row remapper reports a pending remap or a failure: reset the GPU, then rerun"
else
  check "row remapper section not in the layout I expect, read it in the file"
fi
results+=("INFO  history the card arrived with: SBE aggregate $(v DCGM_FI_DEV_ECC_SBE_AGG_TOTAL), correctable remapped rows $(v DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS)")
[ "$(v dcgm_exporter_up)" = "1" ] && pass "DCGM exporter scraped by Prometheus" || fail "DCGM exporter not scraped"

printf '%s\n' "${results[@]}" > "$OUT/session-d-$LABEL-verdict.txt"
echo; printf '  %s\n' "${results[@]}"; echo
log "evidence in docs/artifacts/session-d-$LABEL.txt"
