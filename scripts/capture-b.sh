#!/usr/bin/env bash
#
# Capture Session B's evidence from Prometheus and Alertmanager into
# docs/artifacts/, and check it against the acceptance test in
# docs/02-observability.md.
#
#   scripts/capture-b.sh           during the session, with the GPU node up
#   scripts/capture-b.sh history   after make down: is the history still there?
#
# Everything goes through the Kubernetes API server's service proxy, so there is
# no port-forward to hold open and no UI to screenshot. The one screenshot the
# acceptance test wants, the dashboard, is still yours to take.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl jq
require_kubeconfig

MODE="${1:-live}"
OUT="$REPO_ROOT/docs/artifacts"
PROM="/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy"
AM="/api/v1/namespaces/monitoring/services/kube-prometheus-stack-alertmanager:9093/proxy"
mkdir -p "$OUT"

enc() { jq -rn --arg q "$1" '$q|@uri'; }
query() { kubectl_cp get --raw "$PROM/api/v1/query?query=$(enc "$1")"; }
query_range() {
  local q="$1" hours="$2" step="$3" end start
  end="$(date -u +%s)"; start=$(( end - hours * 3600 ))
  kubectl_cp get --raw "$PROM/api/v1/query_range?query=$(enc "$q")&start=$start&end=$end&step=$step"
}

results=()
record() { results+=("$1"); }

verdict() {
  local file="$1"
  printf '%s\n' "${results[@]}" > "$file"
  echo
  printf '  %s\n' "${results[@]}"
  echo
  log "evidence in docs/artifacts/$(basename "$file") and the session-b-*.txt beside it"
}

########################################
# After make down: criterion 5
########################################

if [ "$MODE" = "history" ]; then
  log "is the GPU's history still in Prometheus with the GPU node gone?"
  gpu_nodes="$(kubectl_cp get nodes -l feature.node.kubernetes.io/pci-10de.present=true -o name | wc -l | tr -d ' ')"
  peak="$(query 'max(max_over_time(DCGM_FI_DEV_GPU_UTIL[6h]))' | jq -r '.data.result[0].value[1] // "none"')"
  samples="$(query 'sum(count_over_time(DCGM_FI_DEV_GPU_UTIL[6h]))' | jq -r '.data.result[0].value[1] // "0"')"
  {
    echo "captured_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "gpu_nodes_in_cluster=$gpu_nodes"
    echo "max GPU utilisation over the last 6h: $peak"
    echo "GPU utilisation samples over the last 6h: $samples"
  } | tee "$OUT/session-b-history.txt"
  if [ "$gpu_nodes" = "0" ] && [ "$samples" != "0" ] && [ "$peak" != "none" ]; then
    record "PASS  history survives the GPU node: $samples samples, peak ${peak}%, with no GPU node in the cluster"
  else
    record "FAIL  gpu_nodes=$gpu_nodes samples=$samples peak=$peak"
  fi
  verdict "$OUT/session-b-history-verdict.txt"
  exit 0
fi

########################################
# Criterion 1: the exporter is scraped, and every counter is there
########################################

log "DCGM exporter scrape targets"
kubectl_cp get --raw "$PROM/api/v1/targets?state=active" \
  | jq -r '.data.activeTargets[]
      | select(.labels.service == "nvidia-dcgm-exporter")
      | "\(.labels.pod)  health=\(.health)  last_scrape=\(.lastScrape)  error=\(.lastError)"' \
  | tee "$OUT/session-b-targets.txt"

if grep -q "health=up" "$OUT/session-b-targets.txt"; then
  record "PASS  Prometheus scrapes the DCGM exporter"
else
  record "FAIL  no healthy DCGM exporter target"
fi

log "every counter in the custom set"
missing=0
: > "$OUT/session-b-counters.txt"
while read -r metric; do
  n="$(query "count($metric)" | jq -r '.data.result[0].value[1] // "0"')"
  case "$metric" in
    DCGM_EXP_XID_ERRORS_TOTAL | DCGM_EXP_CLOCK_EVENTS_TOTAL | DCGM_FI_DEV_XID_ERRORS)
      # The two EXP counters have one series per xid or per clock event reason,
      # and a series only exists once its first event has happened. The raw
      # XID field is blank in DCGM until the first XID since boot, and the
      # exporter skips blank values, so it has no series either. Absent is
      # correct on a healthy GPU, not a missing counter.
      if [ "$n" = "0" ]; then state="no series yet (created on first event)"; else state="present, $n series"; fi ;;
    *)
      if [ "$n" = "0" ]; then state="MISSING"; missing=$((missing + 1)); else state="present, $n series"; fi ;;
  esac
  printf '%-45s %s\n' "$metric" "$state" | tee -a "$OUT/session-b-counters.txt"
done < <(grep -oE '^\s+DCGM_(FI|EXP)_[A-Z0-9_]+, (gauge|counter)' "$REPO_ROOT/gitops/values/gpu-operator.yaml" \
         | sed -E 's/^\s+//; s/,.*//')

if [ "$missing" = "0" ]; then
  record "PASS  every counter in the custom set is being exported"
else
  record "FAIL  $missing counter(s) missing, see session-b-counters.txt"
fi

########################################
# Criterion 3: an alert observed pending, then firing
#
# Prometheus keeps an ALERTS series for every alert while it is pending or
# firing, so the lifecycle can be read back afterwards instead of watched.
########################################

log "alert lifecycle over the last 3 hours, from Prometheus's own ALERTS series"
query_range 'ALERTS{alertname=~"GPU.*|DCGM.*"}' 3 15 \
  | jq -r '.data.result[]
      | "\(.metric.alertname)  \(.metric.alertstate)  first=\(.values[0][0] | todate)  last=\(.values[-1][0] | todate)  xid=\(.metric.xid // "-")"' \
  | sort | tee "$OUT/session-b-alert-timeline.txt"

if grep -q "^GPUUtilisationCollapse  pending" "$OUT/session-b-alert-timeline.txt" \
  && grep -q "^GPUUtilisationCollapse  firing" "$OUT/session-b-alert-timeline.txt"; then
  record "PASS  GPUUtilisationCollapse went pending, then firing"
else
  record "FAIL  GPUUtilisationCollapse not seen both pending and firing yet"
fi

if grep -q "^GPUXidCritical  firing" "$OUT/session-b-alert-timeline.txt"; then
  record "INFO  GPUXidCritical fired. If this followed make inject-xid-dcgm, it was SIMULATED"
fi

log "what Alertmanager holds right now"
kubectl_cp get --raw "$AM/api/v2/alerts" \
  | jq -r '.[] | select(.labels.alertname | test("^(GPU|DCGM)"))
      | "\(.labels.alertname)  state=\(.status.state)  since=\(.startsAt)  severity=\(.labels.severity)"' \
  | tee "$OUT/session-b-alertmanager.txt"

########################################
# The open question from Session A: why did the exporter restart?
########################################

log "DCGM exporter restarts"
restarts="$(query 'max(kube_pod_container_status_restarts_total{namespace="gpu-operator", pod=~"nvidia-dcgm-exporter-.*"})' \
  | jq -r '.data.result[0].value[1] // "unknown"')"
echo "restarts=$restarts" | tee "$OUT/session-b-exporter-restarts.txt"
if [ "$restarts" != "0" ] && [ "$restarts" != "unknown" ]; then
  pod="$(kubectl_cp -n gpu-operator get pods -l app=nvidia-dcgm-exporter -o jsonpath='{.items[0].metadata.name}')"
  {
    echo "== last termination"
    kubectl_cp -n gpu-operator get pod "$pod" \
      -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.lastState.terminated.reason} exit={.lastState.terminated.exitCode} at {.lastState.terminated.finishedAt}{"\n"}{end}'
    echo "== previous container log, last 40 lines"
    kubectl_cp -n gpu-operator logs "$pod" --previous --tail=40 2>&1
  } | tee -a "$OUT/session-b-exporter-restarts.txt"
fi
record "INFO  DCGM exporter restarts this session: $restarts"

verdict "$OUT/session-b-acceptance.txt"
