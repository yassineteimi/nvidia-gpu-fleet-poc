#!/usr/bin/env bash
#
# Parse the time slicing config in gitops/values/gpu-operator-time-slicing.yaml
# with the NVIDIA device plugin's own config loader, at the version the GPU
# Operator deploys (v0.20.0). The module is vendored, so no downloads beyond
# the checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="v0.20.0"
DIR="${KDP_DIR:-${TMPDIR:-/tmp}/k8s-device-plugin-$VERSION}"

if [ ! -d "$DIR/.git" ]; then
  git clone --quiet --depth 1 --branch "$VERSION" https://github.com/NVIDIA/k8s-device-plugin.git "$DIR"
fi

TS_CONFIG="$(python3 -c '
import sys, yaml
v = yaml.safe_load(open(sys.argv[1]))
c = v["devicePlugin"]["config"]
print(c["data"][c["default"]])
' "$REPO_ROOT/gitops/values/gpu-operator-time-slicing.yaml")"
export TS_CONFIG

cp "$REPO_ROOT/tests/time-slicing/zz_time_slicing_test.go" "$DIR/api/config/v1/"
trap 'rm -f "$DIR/api/config/v1/zz_time_slicing_test.go"' EXIT
cd "$DIR"
go test -mod=vendor -count=1 -run TestTimeSlicingConfigParses ./api/config/v1/ -v 2>&1 | grep -E '^(--- |ok|FAIL|\s+zz_)'
