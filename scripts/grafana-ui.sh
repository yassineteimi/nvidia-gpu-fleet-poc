#!/usr/bin/env bash
#
# Print the Grafana admin credentials and port-forward the UI. Same shape as
# argocd-ui.sh, for the same reason: print the password on a line of its own
# rather than hand over a command that pipes it through base64 -d.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl
require_kubeconfig

NS="monitoring"
SECRET="kube-prometheus-stack-grafana"
PORT="${GRAFANA_LOCAL_PORT:-3000}"

user="$(kubectl_cp -n "$NS" get secret "$SECRET" -o go-template='{{index .data "admin-user" | base64decode}}' 2>/dev/null || true)"
pass="$(kubectl_cp -n "$NS" get secret "$SECRET" -o go-template='{{index .data "admin-password" | base64decode}}' 2>/dev/null || true)"
[ -n "$pass" ] || die "no Grafana admin secret in $NS yet. Is kube-prometheus-stack synced in ArgoCD?"

cat <<TXT

  user:      ${user:-admin}
  password:  $pass
  URL:       http://localhost:$PORT/d/gpu-fleet

The GPU fleet dashboard is provisioned from Git. Changes made in the UI are not
kept. Ctrl-C to stop the port-forward.

TXT

exec kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" port-forward svc/kube-prometheus-stack-grafana "$PORT:80"
