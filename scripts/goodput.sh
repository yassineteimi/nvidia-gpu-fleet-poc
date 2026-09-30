#!/usr/bin/env bash
#
# The Session D goodput run: a training Job in tenant-a, interrupted by an
# injected XID 79, resumed from its checkpoint in Garage, and measured.
#
#   scripts/goodput.sh prepull    pull the trainer image onto the GPU node, timed
#   scripts/goodput.sh start      submit workloads/goodput/job.yaml
#   scripts/goodput.sh status     where the Job and its pods are
#   scripts/goodput.sh capture    once the Job is complete: the step logs from
#                                 the bucket, the Job's own timestamps, and the
#                                 goodput analysis over them
#
# The interruption itself is Session C's tooling, with its evidence filed
# under session-d-*:
#   SESSION=d make inject-xid NODE=<gpu node> XID=79
#   SESSION=d make return-to-service NODE=<gpu node>
#
# The evicted pod is deleted by the eviction, and its container log with it.
# That's why each attempt writes its own step log to the bucket: the analysis
# never depends on a pod that no longer exists.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl jq python3
require_kubeconfig

NS="tenant-a"
JOB="goodput"
JOB_YAML="$REPO_ROOT/workloads/goodput/job.yaml"
OUT="$REPO_ROOT/docs/artifacts"
TIMELINE="$OUT/session-d-timeline.txt"
GPU_SELECTOR="nvidia.com/gpu.present=true"
mkdir -p "$OUT"

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

image() {
  local img
  img="$(awk '/image: ghcr.io\/yassineteimi\/goodput-trainer@/ {print $2}' "$JOB_YAML")"
  case "$img" in
    *@sha256:PENDING | "") die "workloads/goodput/job.yaml doesn't pin a trainer image digest yet" ;;
  esac
  echo "$img"
}

# A pod on the GPU node running the trainer image with the bucket's
# credentials, without a GPU. Used for the pre-pull and for reading the logs.
one_off_pod() {
  local name="$1" img="$2"
  shift 2
  local args
  args="$(printf '%s\n' "$@" | jq -R . | jq -sc .)"
  kubectl_cp -n "$NS" delete pod "$name" --ignore-not-found --wait >/dev/null
  kubectl_cp -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $name
spec:
  restartPolicy: Never
  nodeSelector:
    ${GPU_SELECTOR%%=*}: "${GPU_SELECTOR#*=}"
  containers:
    - name: main
      image: $img
      command: $args
      envFrom:
        - secretRef:
            name: checkpoint-s3
YAML
}

wait_done() {
  local name="$1" timeout="$2" phase="" deadline
  deadline=$(( $(date +%s) + timeout ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    phase="$(kubectl_cp -n "$NS" get pod "$name" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "$phase" in Succeeded | Failed) break ;; esac
    sleep 5
  done
  echo "$phase"
}

case "${1:-status}" in
  prepull)
    img="$(image)"
    log "pulling $img onto the GPU node, about 4 GB"
    started="$(stamp)"
    one_off_pod trainer-prepull "$img" python -c "import torch; print('torch', torch.__version__)"
    phase="$(wait_done trainer-prepull 1800)"
    {
      echo "prepull started=$started finished=$(stamp) phase=$phase image=$img"
      kubectl_cp -n "$NS" get events --field-selector involvedObject.name=trainer-prepull \
        -o custom-columns='LAST:.lastTimestamp,REASON:.reason,MESSAGE:.message' | grep -E 'LAST|Pull' || true
      kubectl_cp -n "$NS" logs trainer-prepull 2>&1 || true
    } | tee "$OUT/session-d-prepull.txt"
    kubectl_cp -n "$NS" delete pod trainer-prepull --wait=false >/dev/null
    [ "$phase" = "Succeeded" ] || die "the pre-pull pod ended $phase. See docs/artifacts/session-d-prepull.txt"
    ;;

  start)
    image >/dev/null
    kubectl_cp -n "$NS" get secret checkpoint-s3 >/dev/null || die "no checkpoint-s3 Secret in $NS; is the checkpoint-store Application synced?"
    if kubectl_cp -n "$NS" get job "$JOB" >/dev/null 2>&1; then
      die "a $JOB Job already exists in $NS. Capture it first, then: kubectl -n $NS delete job $JOB"
    fi
    kubectl_cp apply -f "$JOB_YAML"
    uid="$(kubectl_cp -n "$NS" get job "$JOB" -o jsonpath='{.metadata.uid}')"
    echo "goodput_submitted=$(stamp) run_id=$uid" | tee -a "$TIMELINE"
    log "waiting for the trainer to start"
    kubectl_cp -n "$NS" wait pod -l job-name="$JOB" --for=condition=Ready --timeout=600s >/dev/null
    sleep 20
    kubectl_cp -n "$NS" logs -l job-name="$JOB" --tail=5
    log "training. Let it pass at least two checkpoints (step 400), then inject the XID"
    ;;

  status)
    kubectl_cp -n "$NS" get job "$JOB" -o wide 2>/dev/null || { log "no $JOB Job"; exit 0; }
    kubectl_cp -n "$NS" get pods -l job-name="$JOB" -o wide
    kubectl_cp -n "$NS" logs -l job-name="$JOB" --tail=3 2>/dev/null || true
    ;;

  capture)
    job_json="$(kubectl_cp -n "$NS" get job "$JOB" -o json)"
    uid="$(jq -r .metadata.uid <<<"$job_json")"
    start="$(jq -r '.status.startTime // empty' <<<"$job_json")"
    end="$(jq -r '.status.completionTime // empty' <<<"$job_json")"
    [ -n "$end" ] || die "the $JOB Job hasn't completed; nothing to measure yet"

    log "reading run $uid's step logs from the bucket"
    one_off_pod goodput-dump "$(image)" python -m trainer.dump "$uid"
    phase="$(wait_done goodput-dump 300)"
    [ "$phase" = "Succeeded" ] || die "the log dump pod ended $phase: $(kubectl_cp -n "$NS" logs goodput-dump 2>&1 | tail -5)"
    dir="$OUT/session-d-goodput"
    rm -rf "$dir" && mkdir -p "$dir"
    # stderr shares the log stream; the dump is the one JSON line at the end.
    kubectl_cp -n "$NS" logs goodput-dump | tail -n 1 > "$dir/logs.json"
    jq -e 'type == "object" and length > 0' "$dir/logs.json" >/dev/null || die "no step logs for run $uid in the bucket"
    kubectl_cp -n "$NS" delete pod goodput-dump --wait=false >/dev/null
    for attempt in $(jq -r 'keys[]' "$dir/logs.json"); do
      jq -r --arg a "$attempt" '.[$a]' "$dir/logs.json" > "$dir/$attempt.jsonl"
    done
    rm "$dir/logs.json"

    {
      echo "captured_at=$(stamp) run_id=$uid"
      echo "job_start=$start job_completion=$end"
      jq -r '.status | "succeeded=\(.succeeded // 0) failed=\(.failed // 0)"' <<<"$job_json"
      echo "== Job conditions"
      jq -r '.status.conditions[]? | "\(.lastTransitionTime) \(.type)=\(.status) \(.reason // "") \(.message // "")"' <<<"$job_json"
      echo "== Job events"
      kubectl_cp -n "$NS" get events --field-selector "involvedObject.kind=Job,involvedObject.name=$JOB" \
        --sort-by=.lastTimestamp -o custom-columns='LAST:.lastTimestamp,REASON:.reason,MESSAGE:.message'
      echo "== pods of the Job still in the API"
      kubectl_cp -n "$NS" get pods -l job-name="$JOB" -o wide
      echo "== attempts in the bucket"
      ls "$dir"
    } | tee "$OUT/session-d-goodput-job.txt"

    log "goodput, from the step logs and the Job's own start and completion times"
    (
      cd "$REPO_ROOT/workloads/goodput" || exit 1
      python3 -m trainer.goodput "$dir"/*.jsonl \
        --job-start "$(jq -rn --arg t "$start" '$t|fromdateiso8601')" \
        --job-end "$(jq -rn --arg t "$end" '$t|fromdateiso8601')"
    ) | tee "$OUT/session-d-goodput.json"
    ;;

  *) die "usage: scripts/goodput.sh prepull|start|status|capture" ;;
esac
