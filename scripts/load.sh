#!/usr/bin/env bash
#
# Real GPU load for Session B, and a real kill.
#
#   scripts/load.sh start    tensor load on the GPU for LOAD_SECONDS (default 1200)
#   scripts/load.sh stop     kill it, which is what GPUUtilisationCollapse detects
#   scripts/load.sh status
#
# The load is dcgmproftester from the DCGM image the GPU Operator already
# runs, so nothing new is pulled onto a node that bills by the hour.
#   -t 1004                 hold DCGM_FI_PROF_PIPE_TENSOR_ACTIVE (field 1004,
#                           dcgmlib/dcgm_fields.h) at its target
#   --target-max-value      at the maximum, steadily, rather than stepping
#   --no-dcgm-validation    only generate the workload. The standalone DCGM
#                           host engine already holds the profiling
#                           infrastructure, and dcgmproftester's own error text
#                           names this flag as the way round that
# It runs as root, which its source says it needs.
#
# Start and kill times are written to docs/artifacts so the write up can line
# the alert up against when the job actually died.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl
require_kubeconfig

DCGM_IMAGE="${DCGM_IMAGE:-nvcr.io/nvidia/cloud-native/dcgm:4.6.0-1-ubuntu24.04}"
LOAD_SECONDS="${LOAD_SECONDS:-1200}"
NS="gpu-load"
JOB="gpu-load"
TIMELINE="$REPO_ROOT/docs/artifacts/session-b-load-timeline.txt"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

case "${1:-status}" in
  start)
    kubectl_cp create namespace "$NS" --dry-run=client -o yaml | kubectl_cp apply -f - >/dev/null
    kubectl_cp -n "$NS" delete job "$JOB" --ignore-not-found --wait >/dev/null
    kubectl_cp -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB
spec:
  backoffLimit: 0
  activeDeadlineSeconds: $((LOAD_SECONDS + 600))
  template:
    metadata:
      labels:
        app.kubernetes.io/part-of: gpu-load
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
                  echo "using \$b"
                  exec "\$b" --no-dcgm-validation --target-max-value -t 1004 -d $LOAD_SECONDS
                fi
              done
              echo "no dcgmproftester in this image" >&2
              exit 1
          resources:
            limits:
              nvidia.com/gpu: 1
YAML
    log "load job submitted, waiting for it to start on the GPU"
    kubectl_cp -n "$NS" wait pod -l job-name="$JOB" --for=condition=PodScheduled --timeout=120s >/dev/null
    deadline=$(( $(date +%s) + 600 ))
    phase=""
    while [ "$(date +%s)" -lt "$deadline" ]; do
      phase="$(kubectl_cp -n "$NS" get pod -l job-name="$JOB" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)"
      case "$phase" in Running | Failed | Succeeded) break ;; esac
      sleep 5
    done

    # This is the first time dcgmproftester runs anywhere with a driver: on the
    # control plane it cannot start at all, for lack of libcuda. If it rejects
    # its flags it exits at once, so look again after twenty seconds rather than
    # finding out ten billed minutes later.
    [ "$phase" = "Running" ] && sleep 20
    phase="$(kubectl_cp -n "$NS" get pod -l job-name="$JOB" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)"
    kubectl_cp -n "$NS" logs job/"$JOB" --tail=15 2>/dev/null | tee "$REPO_ROOT/docs/artifacts/session-b-load-start.txt" || true
    if [ "$phase" != "Running" ]; then
      die "the load job is $phase, not Running, twenty seconds in. Its log is above and in docs/artifacts/session-b-load-start.txt"
    fi
    mkdir -p "$(dirname "$TIMELINE")"
    echo "load_started=$(now) duration_requested_s=$LOAD_SECONDS" | tee -a "$TIMELINE"
    log "running. Leave it at least ten minutes, then: make load-stop"
    ;;

  stop)
    kubectl_cp -n "$NS" get job "$JOB" >/dev/null 2>&1 || die "no load job to kill"
    kubectl_cp -n "$NS" logs job/"$JOB" --tail=20 2>/dev/null | tee "$REPO_ROOT/docs/artifacts/session-b-load-job.txt" || true
    echo "load_killed=$(now)" | tee -a "$TIMELINE"
    kubectl_cp -n "$NS" delete job "$JOB" --grace-period=0 --wait=false
    log "killed. GPUUtilisationCollapse should go pending within about three minutes and fire a minute later"
    ;;

  status)
    kubectl_cp -n "$NS" get job,pods -o wide 2>/dev/null || log "no load job"
    ;;

  *) die "usage: scripts/load.sh start|stop|status" ;;
esac
