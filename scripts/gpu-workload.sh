#!/usr/bin/env bash
#
# A GPU workload for Session C to evict: a Deployment holding the node's one
# GPU. It's a Deployment so that after the drain its replacement pod waits,
# Pending, with nowhere to go, and is scheduled again once the node is back.
#
#   scripts/gpu-workload.sh start|stop|status
#
# It exits promptly on SIGTERM, like a well behaved training job with a
# checkpoint handler would, so the drain time measures the drain and not a
# 30 second kill timeout.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl
require_kubeconfig

NS="gpu-work"
IMAGE="nvcr.io/nvidia/cuda:12.6.0-base-ubuntu22.04"

case "${1:-status}" in
  start)
    kubectl_cp create namespace "$NS" --dry-run=client -o yaml | kubectl_cp apply -f - >/dev/null
    kubectl_cp apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-workload
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels: { app: gpu-workload }
  template:
    metadata:
      labels: { app: gpu-workload }
    spec:
      containers:
        - name: work
          image: $IMAGE
          command: ["sh", "-c"]
          args:
            - trap 'echo SIGTERM, exiting; exit 0' TERM; nvidia-smi -L; while true; do sleep 1; done
          resources:
            limits:
              nvidia.com/gpu: 1
YAML
    kubectl_cp -n "$NS" rollout status deploy/gpu-workload --timeout=300s
    kubectl_cp -n "$NS" get pods -o wide
    ;;
  stop)
    kubectl_cp delete namespace "$NS" --wait=false
    ;;
  status)
    kubectl_cp -n "$NS" get pods -o wide 2>/dev/null || log "no workload"
    ;;
  *) die "usage: scripts/gpu-workload.sh start|stop|status" ;;
esac
