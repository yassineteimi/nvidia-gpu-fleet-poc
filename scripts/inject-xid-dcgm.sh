#!/usr/bin/env bash
#
# SIMULATED. Inject an XID into DCGM's field cache on the GPU node.
#
# The GPU did not fail. This writes a value for DCGM_FI_DEV_XID_ERRORS (field
# 230, dcgmlib/dcgm_fields.h) into the standalone host engine's cache with
# `dcgmi test --inject`, to exercise everything downstream of DCGM for real:
# the exporter's XID counter, Prometheus, the GPUXidCritical rule and
# Alertmanager. It is listed on the What is simulated page.
#
# Whether the exporter's counter, which reads DCGM with GetValuesSince, picks up
# an injected value is exactly what this finds out. If it does not, that is a
# finding, and the rule stays proven by its promtool tests alone.
#
# Session C injects differently, as a kernel log line, because that is what
# node-problem-detector reads.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl
require_kubeconfig

XID="${1:-79}"
POD="$(kubectl_cp -n gpu-operator get pods -l app=nvidia-dcgm -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[ -n "$POD" ] || die "no standalone DCGM pod (app=nvidia-dcgm) in gpu-operator. Is the GPU node up?"

warn "SIMULATED: injecting XID $XID into DCGM's cache on $POD. The GPU is fine."
kubectl_cp -n gpu-operator exec "$POD" -- dcgmi test --inject --gpuid 0 -f 230 -v "$XID" \
  | tee "$REPO_ROOT/docs/artifacts/session-b-xid-injection.txt"
echo "xid_injected=$(date -u +%Y-%m-%dT%H:%M:%SZ) xid=$XID simulated=true" \
  | tee -a "$REPO_ROOT/docs/artifacts/session-b-load-timeline.txt"
log "GPUXidCritical should fire on the next rule evaluation if the exporter counted it"
