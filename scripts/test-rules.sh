#!/usr/bin/env bash
#
# Unit test the GPU alert rules offline, with no cluster.
#
# The rules live in a PrometheusRule resource so ArgoCD can deploy them.
# promtool reads plain Prometheus rule files, so this lifts everything under
# spec: into a temporary rules file first. That relies on spec being the last
# top-level key in gpu-alerts.yaml, which the file says at the top.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools promtool sed

SRC="$REPO_ROOT/gitops/manifests/observability"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sed -n '/^spec:/,$p' "$SRC/gpu-alerts.yaml" | sed '1d; s/^  //' > "$WORK/gpu-alerts.rules.yaml"
cp "$SRC/tests/gpu-alerts.test.yaml" "$WORK/"

log "promtool $(promtool --version 2>&1 | head -n1 | awk '{print $3}')"
log "checking rule syntax"
promtool check rules "$WORK/gpu-alerts.rules.yaml"

log "running unit tests"
(cd "$WORK" && promtool test rules gpu-alerts.test.yaml)
