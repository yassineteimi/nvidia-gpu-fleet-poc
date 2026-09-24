#!/usr/bin/env bash
#
# The free check before Session B's billed hour: does the DCGM image carry the
# two tools B2 depends on? Runs on the control plane, needs no GPU, costs
# nothing.
#
#   dcgmproftester  generates the real tensor load for the utilisation
#                   collapse alert, with no extra image to pull onto the GPU
#                   node while it bills
#   dcgmi test      injects a value into DCGM's cache, for the optional,
#                   simulated XID
#
# Both were checked against DCGM's source (dcgmproftester/Arguments.h and
# dcgmi/CommandLineParser.cpp). This checks they are in the image that will
# actually run.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl
require_kubeconfig

# The standalone DCGM image the GPU Operator deploys: chart v26.7.0 default for
# dcgm.version, not overridden in gitops/values/gpu-operator.yaml.
DCGM_IMAGE="${DCGM_IMAGE:-nvcr.io/nvidia/cloud-native/dcgm:4.6.0-1-ubuntu24.04}"
NS="gpu-fleet-checks"
POD="dcgm-image-check"
OUT="$REPO_ROOT/docs/artifacts/session-b-dcgm-image-check.txt"

kubectl_cp create namespace "$NS" --dry-run=client -o yaml | kubectl_cp apply -f - >/dev/null
kubectl_cp -n "$NS" delete pod "$POD" --ignore-not-found --wait >/dev/null

log "running $DCGM_IMAGE on the control plane, no GPU"
kubectl_cp -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $POD
spec:
  restartPolicy: Never
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  containers:
    - name: check
      image: $DCGM_IMAGE
      command: ["sh", "-c"]
      args:
        - |
          echo "== image"; echo "$DCGM_IMAGE"
          echo "== dcgmi version"; dcgmi --version 2>&1 | head -n 3
          echo "== dcgmproftester binaries"; ls -1 /usr/bin/dcgmproftester* 2>&1
          for b in /usr/bin/dcgmproftester*; do
            [ -x "\$b" ] || continue
            echo "== \$b: shared libraries it cannot find here"
            ldd "\$b" 2>&1 | grep "not found" || echo "none"
            echo "== \$b --help, first lines, unfiltered"
            "\$b" --help 2>&1 | head -n 12
          done
          echo "== dcgmi test --help (injection)"
          dcgmi test --help 2>&1 | grep -E -- '--inject|--field|--value|--gpuid' | head -n 8
YAML

if ! kubectl_cp -n "$NS" wait "pod/$POD" --for=jsonpath='{.status.phase}'=Succeeded --timeout=600s; then
  kubectl_cp -n "$NS" describe pod "$POD" | tail -n 20 >&2
  die "the check pod did not complete"
fi

mkdir -p "$(dirname "$OUT")"
kubectl_cp -n "$NS" logs "$POD" | tee "$OUT"
kubectl_cp delete namespace "$NS" --wait=false >/dev/null

echo
grep -q 'dcgmproftester[0-9]' "$OUT" && log "PASS  dcgmproftester is in the image" || warn "FAIL  no dcgmproftester: B2 needs another load generator"
# dcgmproftester links against libcuda, which only exists where there is an
# NVIDIA driver. On the control plane its --help cannot even start, so a flag
# missing from its help here proves nothing either way. The first version of
# this script piped that failure through grep and reported it as FAIL.
if grep -q -- '--no-dcgm-validation' "$OUT"; then
  log "PASS  it takes --no-dcgm-validation"
elif grep -q 'libcuda.* not found' "$OUT"; then
  warn "INCONCLUSIVE  dcgmproftester needs libcuda, which only exists on a GPU node."
  warn "              Its flags are confirmed by the first make load in B2 instead."
else
  warn "FAIL  --help ran and does not mention --no-dcgm-validation"
fi
grep -q -- '--inject' "$OUT" && log "PASS  dcgmi test supports --inject" || warn "FAIL  no --inject: the simulated XID is off the table"
log "saved to docs/artifacts/session-b-dcgm-image-check.txt"
