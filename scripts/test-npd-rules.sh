#!/usr/bin/env bash
#
# Run the node-problem-detector GPU monitor's tests through node-problem-detector
# itself, at the version the cluster deploys. The test file is copied into the
# upstream systemlogmonitor package so it can drive the real log buffer and
# condition logic; the module is vendored, so the build needs no downloads
# beyond the checkout.
#
#   scripts/test-npd-rules.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NPD_VERSION="v1.36.0"
NPD_DIR="${NPD_DIR:-${TMPDIR:-/tmp}/node-problem-detector-$NPD_VERSION}"
HERE="$REPO_ROOT/gitops/manifests/node-problem-detector"

if [ ! -d "$NPD_DIR/.git" ]; then
  git clone --quiet --depth 1 --branch "$NPD_VERSION" \
    https://github.com/kubernetes/node-problem-detector.git "$NPD_DIR"
fi

cp "$HERE/tests/gpu_monitor_test.go" "$NPD_DIR/pkg/systemlogmonitor/zz_gpu_monitor_test.go"
trap 'rm -f "$NPD_DIR/pkg/systemlogmonitor/zz_gpu_monitor_test.go"' EXIT

cd "$NPD_DIR"
GPU_MONITOR_CONFIG="$HERE/gpu-monitor.json" \
  go test -mod=vendor -count=1 -run 'Xid|Shape|Ignored|Fault|FirstFault' ./pkg/systemlogmonitor/ -v 2>&1 \
  | grep -E '^(=== RUN|--- |PASS|FAIL|ok|\s+zz_)' 
