#!/usr/bin/env bash
#
# Session D time slicing and tenancy on the one L4.
#
#   scripts/tenancy.sh wait-slicing  after the time slicing commit: wait for the
#                                    node to advertise 4 GPUs, and time it
#   scripts/tenancy.sh start         two GPU pods in tenant-a, one in tenant-b,
#                                    then a third in tenant-a, which the quota
#                                    must refuse
#   scripts/tenancy.sh capture       the evidence, with a PASS/FAIL per check
#   scripts/tenancy.sh stop
#
# Each pod holds a different amount of GPU memory (1, 2 and 3 GiB), so the
# node-wide nvidia-smi process list says which process is which tenant's. That
# list comes from the GPU Operator's driver container, which runs in the host
# PID namespace; a tenant's own container only sees itself.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl jq
require_kubeconfig

OUT="$REPO_ROOT/docs/artifacts"
TIMELINE="$OUT/session-d-timeline.txt"
JOB_YAML="$REPO_ROOT/workloads/goodput/job.yaml"
mkdir -p "$OUT"

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
gpu_node() { kubectl_cp get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.name}'; }
allocatable() { kubectl_cp get node "$1" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'; }

# The trainer image is already on the node after goodput.sh prepull, so these
# pods start in seconds and pull nothing.
image() { awk '/image: ghcr.io\/yassineteimi\/goodput-trainer@/ {print $2}' "$JOB_YAML"; }

share_pod() {
  local ns="$1" name="$2" gib="$3"
  kubectl_cp -n "$ns" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $name
  labels: { app.kubernetes.io/name: gpu-share }
spec:
  restartPolicy: Never
  terminationGracePeriodSeconds: 5
  containers:
    - name: main
      image: $(image)
      command: ["python3", "-c"]
      args:
        - |
          import os, time, torch
          hold = torch.empty($gib * 2**30, dtype=torch.uint8, device="cuda")
          p = torch.cuda.get_device_properties(0)
          print("$ns/$name", p.name, "uuid", getattr(p, "uuid", "n/a"), "holding $gib GiB", flush=True)
          x = torch.randn(4096, 4096, device="cuda")
          while True:
              x = x @ x
              x = x / x.norm()
              torch.cuda.synchronize()
              time.sleep(0.5)
      resources:
        limits:
          nvidia.com/gpu: 1
YAML
}

case "${1:-}" in
  wait-slicing)
    node="$(gpu_node)"
    [ -n "$node" ] || die "no GPU node in the cluster"
    echo "slicing_wait_started=$(stamp) node=$node allocatable_before=$(allocatable "$node")" | tee -a "$TIMELINE"
    deadline=$(( $(date +%s) + 900 ))
    until [ "$(allocatable "$node")" = "4" ]; do
      [ "$(date +%s)" -lt "$deadline" ] || die "$node still advertises $(allocatable "$node") GPUs after 15 minutes"
      sleep 5
    done
    echo "gpu_allocatable_4=$(stamp) node=$node" | tee -a "$TIMELINE"
    ;;

  start)
    case "$(image)" in "" | *PENDING) die "no trainer image digest pinned in workloads/goodput/job.yaml" ;; esac
    share_pod tenant-a share-a1 1
    share_pod tenant-a share-a2 2
    share_pod tenant-b share-b1 3
    kubectl_cp -n tenant-a wait pod share-a1 share-a2 --for=condition=Ready --timeout=300s
    kubectl_cp -n tenant-b wait pod share-b1 --for=condition=Ready --timeout=300s
    echo "tenants_running=$(stamp)" | tee -a "$TIMELINE"

    log "a third GPU pod in tenant-a, which its quota of 2 must refuse"
    set +e
    share_pod tenant-a share-a3 1 > "$OUT/session-d-quota-refusal.txt" 2>&1
    rc=$?
    set -e
    cat "$OUT/session-d-quota-refusal.txt"
    if [ "$rc" -eq 0 ]; then
      kubectl_cp -n tenant-a delete pod share-a3 --wait=false >/dev/null
      die "the API server accepted a third GPU pod in tenant-a; the quota isn't working"
    fi
    ;;

  capture)
    node="$(gpu_node)"
    results=()
    {
      echo "captured_at=$(stamp) node=$node"
      echo "== what the node advertises"
      kubectl_cp get node "$node" -o json | jq -r '
        "nvidia.com/gpu capacity=\(.status.capacity["nvidia.com/gpu"]) allocatable=\(.status.allocatable["nvidia.com/gpu"])",
        (.metadata.labels | to_entries[] | select(.key | test("^nvidia.com/(gpu.product|gpu.replicas|gpu.sharing-strategy|device-plugin.config)$")) | "\(.key)=\(.value)")'
      echo "== device plugin config in use"
      kubectl_cp -n gpu-operator get configmap device-plugin-config -o jsonpath='{.data}' 2>&1; echo
      echo "== tenant pods"
      kubectl_cp get pods -n tenant-a -o wide -l app.kubernetes.io/name=gpu-share
      kubectl_cp get pods -n tenant-b -o wide -l app.kubernetes.io/name=gpu-share
      echo "== what each pod says it has"
      for p in tenant-a/share-a1 tenant-a/share-a2 tenant-b/share-b1; do
        kubectl_cp -n "${p%/*}" logs "${p#*/}" 2>&1 | head -1
      done
      echo "== quotas"
      kubectl_cp get resourcequota -n tenant-a -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,USED:.status.used,HARD:.status.hard'
      kubectl_cp get resourcequota -n tenant-b -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,USED:.status.used,HARD:.status.hard'
      echo "== the third pod in tenant-a"
      cat "$OUT/session-d-quota-refusal.txt" 2>/dev/null || echo "not attempted"
      echo "== nvidia-smi on the node, from the driver container"
      drv="$(kubectl_cp -n gpu-operator get pods -l app=nvidia-driver-daemonset --field-selector "spec.nodeName=$node" -o jsonpath='{.items[0].metadata.name}')"
      kubectl_cp -n gpu-operator exec "$drv" -c nvidia-driver-ctr -- nvidia-smi 2>&1
    } | tee "$OUT/session-d-tenancy.txt"

    f="$OUT/session-d-tenancy.txt"
    grep -q 'allocatable=4' "$f" && results+=("PASS  the node advertises 4 nvidia.com/gpu") || results+=("FAIL  the node doesn't advertise 4 nvidia.com/gpu")
    [ "$(grep -c ' Running ' <<<"$(grep -E '^share-' "$f")")" -eq 3 ] \
      && results+=("PASS  three GPU pods from two tenants are Running") || results+=("FAIL  not all three tenant pods are Running")
    uuids="$(grep -oE 'uuid [^ ]+' "$f" | sort -u | wc -l | tr -d ' ')"
    [ "$uuids" = "1" ] && results+=("PASS  all three pods report the same GPU UUID") || results+=("CHECK the pods report $uuids distinct GPU UUIDs")
    grep -q 'exceeded quota' "$f" && results+=("PASS  the third tenant-a pod was refused: exceeded quota") || results+=("FAIL  no quota refusal recorded")
    [ "$(grep -cE 'python[0-9.]* +[0-9]+MiB' "$f")" -ge 3 ] \
      && results+=("PASS  nvidia-smi shows at least 3 processes on the GPU") || results+=("CHECK nvidia-smi process list, see the file")
    printf '%s\n' "${results[@]}" > "$OUT/session-d-tenancy-verdict.txt"
    echo; printf '  %s\n' "${results[@]}"; echo
    log "evidence in docs/artifacts/session-d-tenancy.txt"
    ;;

  stop)
    kubectl_cp -n tenant-a delete pod -l app.kubernetes.io/name=gpu-share --wait=false
    kubectl_cp -n tenant-b delete pod -l app.kubernetes.io/name=gpu-share --wait=false
    ;;

  *) die "usage: scripts/tenancy.sh wait-slicing|start|capture|stop" ;;
esac
