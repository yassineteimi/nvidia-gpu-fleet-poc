#!/usr/bin/env bash
#
# Session D burn-in: a scaled-down version of a multi-day acceptance campaign.
#
#   scripts/burn-in.sh diag <before|after>   dcgmi diag -r 3 on the GPU node, timed
#   scripts/burn-in.sh start                 BURN_SECONDS of tensor load (default 3 h)
#   scripts/burn-in.sh status
#   scripts/burn-in.sh capture               once the load Job has completed: the
#                                            stability record from Prometheus over
#                                            exactly the Job's start to completion
#
# The load is Session B's: dcgmproftester holding tensor activity at its
# maximum, from the DCGM image the GPU Operator already runs. It's a Job with
# its own deadline, so it ends on time without anyone at the keyboard, and the
# capture takes its window from the Job's timestamps, not from memory.
#
# Counters (ECC, row remapping, PCIe replays, power and thermal violation time)
# are reported as max minus min over the window. increase() extrapolates at
# the edges, which is the Session B finding about DCGMExporterRestarting.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl jq
require_kubeconfig

DCGM_IMAGE="${DCGM_IMAGE:-nvcr.io/nvidia/cloud-native/dcgm:4.6.0-1-ubuntu24.04}"
BURN_SECONDS="${BURN_SECONDS:-10800}"
NS="gpu-burnin"
JOB="burn-in"
OUT="$REPO_ROOT/docs/artifacts"
TIMELINE="$OUT/session-d-burn-in-timeline.txt"
PROM="/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy"
mkdir -p "$OUT"

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
gpu_node() { kubectl_cp get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.name}'; }
enc() { jq -rn --arg q "$1" '$q|@uri'; }

case "${1:-status}" in
  diag)
    label="${2:?usage: scripts/burn-in.sh diag <before|after>}"
    node="$(gpu_node)"
    [ -n "$node" ] || die "no GPU node in the cluster"
    if [ "$label" = "after" ] && kubectl_cp -n "$NS" get job "$JOB" -o jsonpath='{.status.active}' 2>/dev/null | grep -q 1; then
      die "the burn-in load is still running; the diagnostic needs the GPU to itself"
    fi
    pod="$(kubectl_cp -n gpu-operator get pods -l app=nvidia-dcgm --field-selector "spec.nodeName=$node" -o jsonpath='{.items[0].metadata.name}')"
    [ -n "$pod" ] || die "no nvidia-dcgm pod on $node"
    log "dcgmi diag -r 3 in $pod. Level 3 runs the stress plugins; expect several minutes"
    started="$(stamp)"; t0="$(date +%s)"
    set +e
    kubectl_cp -n gpu-operator exec "$pod" -- dcgmi diag -r 3 2>&1 | tee "$OUT/session-d-diag-$label.txt"
    rc="${PIPESTATUS[0]}"
    set -e
    echo "diag_$label level=3 started=$started finished=$(stamp) seconds=$(( $(date +%s) - t0 )) exit=$rc node=$node" | tee -a "$TIMELINE"
    if [ "$rc" -ne 0 ] || grep -qw "Fail" "$OUT/session-d-diag-$label.txt"; then
      die "dcgmi diag -r 3 did not pass. Don't start or accept the burn-in on this GPU"
    fi
    log "passed"
    ;;

  start)
    [ -n "$(gpu_node)" ] || die "no GPU node in the cluster"
    kubectl_cp create namespace "$NS" --dry-run=client -o yaml | kubectl_cp apply -f - >/dev/null
    if kubectl_cp -n "$NS" get job "$JOB" >/dev/null 2>&1; then
      die "a burn-in Job already exists. Capture it, then: kubectl -n $NS delete job $JOB"
    fi
    kubectl_cp -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB
spec:
  backoffLimit: 0
  activeDeadlineSeconds: $((BURN_SECONDS + 900))
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: dcgmproftester
          image: $DCGM_IMAGE
          securityContext:
            runAsUser: 0
            capabilities:
              add: ["SYS_ADMIN"]
          command: ["sh", "-c"]
          args:
            - |
              for b in /usr/bin/dcgmproftester13 /usr/bin/dcgmproftester12; do
                if [ -x "\$b" ]; then
                  echo "using \$b for $BURN_SECONDS s"
                  exec "\$b" --no-dcgm-validation --target-max-value -t 1004 -d $BURN_SECONDS
                fi
              done
              echo "no dcgmproftester in this image" >&2
              exit 1
          resources:
            limits:
              nvidia.com/gpu: 1
YAML
    kubectl_cp -n "$NS" wait pod -l job-name="$JOB" --for=condition=Ready --timeout=300s >/dev/null
    sleep 30
    phase="$(kubectl_cp -n "$NS" get pod -l job-name="$JOB" -o jsonpath='{.items[0].status.phase}')"
    kubectl_cp -n "$NS" logs job/"$JOB" --tail=10 || true
    [ "$phase" = "Running" ] || die "the burn-in load is $phase thirty seconds in, not Running"
    echo "burn_in_started=$(stamp) seconds_requested=$BURN_SECONDS" | tee -a "$TIMELINE"
    log "running for $((BURN_SECONDS / 60)) minutes. It stops by itself. Afterwards:"
    log "  make burn-in-capture, then make burn-in-diag LABEL=after"
    ;;

  status)
    kubectl_cp -n "$NS" get job,pods -o wide 2>/dev/null || log "no burn-in Job"
    ;;

  capture)
    job_json="$(kubectl_cp -n "$NS" get job "$JOB" -o json)"
    start="$(jq -r '.status.startTime // empty' <<<"$job_json")"
    end="$(jq -r '.status.completionTime // empty' <<<"$job_json")"
    [ -n "$end" ] || die "the burn-in Job hasn't completed ($(jq -c .status <<<"$job_json"))"
    s="$(jq -rn --arg t "$start" '$t|fromdateiso8601')"
    e="$(jq -rn --arg t "$end" '$t|fromdateiso8601')"
    # Skip the first and last minute: ramp up and wind down aren't the steady state.
    d="$(( e - s - 120 ))"
    at="$(( e - 60 ))"
    [ "$d" -gt 600 ] || die "the burn-in ran for only $(( e - s )) s"

    q() { kubectl_cp get --raw "$PROM/api/v1/query?time=$at&query=$(enc "$1")" | jq -r '.data.result[0].value[1] // "no data"'; }
    delta() { q "max(max_over_time($1[${d}s]) - min_over_time($1[${d}s]))"; }

    {
      echo "captured_at=$(stamp) node=$(gpu_node)"
      echo "job_start=$start job_completion=$end succeeded=$(jq -r '.status.succeeded // 0' <<<"$job_json") failed=$(jq -r '.status.failed // 0' <<<"$job_json")"
      echo "window: ${d} s of steady state, from start + 60 s to completion - 60 s"
      echo "== load held"
      echo "tensor active, mean: $(q "avg(avg_over_time(DCGM_FI_PROF_PIPE_TENSOR_ACTIVE[${d}s]))")"
      echo "tensor active, min:  $(q "min(min_over_time(DCGM_FI_PROF_PIPE_TENSOR_ACTIVE[${d}s]))")"
      echo "GPU utilisation, min: $(q "min(min_over_time(DCGM_FI_DEV_GPU_UTIL[${d}s]))")"
      echo "== thermals and power"
      echo "GPU temperature C, mean / max: $(q "avg(avg_over_time(DCGM_FI_DEV_GPU_TEMP[${d}s]))") / $(q "max(max_over_time(DCGM_FI_DEV_GPU_TEMP[${d}s]))")"
      echo "memory temperature C, max: $(q "max(max_over_time(DCGM_FI_DEV_MEMORY_TEMP[${d}s]))")"
      echo "power W, mean / max: $(q "avg(avg_over_time(DCGM_FI_DEV_POWER_USAGE[${d}s]))") / $(q "max(max_over_time(DCGM_FI_DEV_POWER_USAGE[${d}s]))")"
      echo "SM clock MHz, min / mean / max: $(q "min(min_over_time(DCGM_FI_DEV_SM_CLOCK[${d}s]))") / $(q "avg(avg_over_time(DCGM_FI_DEV_SM_CLOCK[${d}s]))") / $(q "max(max_over_time(DCGM_FI_DEV_SM_CLOCK[${d}s]))")"
      echo "time under power violation, us: $(delta DCGM_FI_DEV_POWER_VIOLATION)"
      echo "time under thermal violation, us: $(delta DCGM_FI_DEV_THERMAL_VIOLATION)"
      echo "== errors over the window (max minus min)"
      for m in DCGM_FI_DEV_ECC_SBE_VOL_TOTAL DCGM_FI_DEV_ECC_DBE_VOL_TOTAL DCGM_FI_DEV_ECC_SBE_AGG_TOTAL \
               DCGM_FI_DEV_ECC_DBE_AGG_TOTAL DCGM_FI_DEV_CORRECTABLE_REMAPPED_ROWS \
               DCGM_FI_DEV_UNCORRECTABLE_REMAPPED_ROWS DCGM_FI_DEV_ROW_REMAP_FAILURE DCGM_FI_DEV_PCIE_REPLAY_COUNTER; do
        echo "$m: $(delta "$m")"
      done
      echo "DCGM_FI_DEV_XID_ERRORS changes: $(q "max(changes(DCGM_FI_DEV_XID_ERRORS[${d}s]))") max value: $(q "max(max_over_time(DCGM_FI_DEV_XID_ERRORS[${d}s]))")"
      echo "== telemetry gaps"
      echo "temperature samples in the window: $(q "max(count_over_time(DCGM_FI_DEV_GPU_TEMP[${d}s]))")"
      echo "gpu-operator container restarts: $(q "sum(max_over_time(kube_pod_container_status_restarts_total{namespace=\"gpu-operator\"}[${d}s]) - min_over_time(kube_pod_container_status_restarts_total{namespace=\"gpu-operator\"}[${d}s]))")"
      echo "== clock event reasons, bitmask value: minutes seen"
      kubectl_cp get --raw "$PROM/api/v1/query_range?query=$(enc 'max(DCGM_FI_DEV_CLOCKS_EVENT_REASONS)')&start=$(( s + 60 ))&end=$at&step=60" \
        | jq -r '[.data.result[0].values[]?[1]] | group_by(.) | map("\(.[0]): \(length)") | .[]'
    } | tee "$OUT/session-d-burn-in.txt"

    # The series behind the charts in the write-up, one row a minute.
    series='DCGM_FI_DEV_GPU_TEMP DCGM_FI_DEV_POWER_USAGE DCGM_FI_DEV_SM_CLOCK DCGM_FI_PROF_PIPE_TENSOR_ACTIVE'
    for m in $series; do
      kubectl_cp get --raw "$PROM/api/v1/query_range?query=$(enc "max($m)")&start=$s&end=$e&step=60" \
        | jq -c --arg m "$m" '{($m): ((.data.result[0].values // []) | map({key: (.[0] | tostring), value: .[1]}) | from_entries)}'
    done | jq -rs --arg cols "$series" '
      add as $all | ($cols | split(" ")) as $c
      | ([$all[] | keys[]] | unique | sort_by(tonumber)) as $ts
      | ("time," + ($c | join(","))),
        ($ts[] as $t | ([$t] + [$c[] as $m | ($all[$m][$t] // "")]) | join(","))
    ' > "$OUT/session-d-burn-in-series.csv"
    log "stability record in docs/artifacts/session-d-burn-in.txt, series in session-d-burn-in-series.csv"
    ;;

  *) die "usage: scripts/burn-in.sh diag <before|after>|start|status|capture" ;;
esac
