#!/usr/bin/env bash
#
# Print the ArgoCD admin credentials and open a port-forward to the UI.
#
# This exists because the usual advice, "decode the initial admin secret with
# base64 -d", hands you a password with no trailing newline. The shell prompt
# then renders flush against the last character and you copy the prompt along
# with it, or lose the final character, and conclude the password is wrong.
# Printing it from a script with a newline of its own removes the whole class
# of problem. go-template with base64decode is also portable, where base64 -d
# is GNU and macOS wants -D.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl
require_kubeconfig

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_LOCAL_PORT="${ARGOCD_LOCAL_PORT:-8080}"

password="$(kubectl_cp -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
  -o go-template='{{index .data "password" | base64decode}}' 2>/dev/null || true)"

echo
if [ -n "$password" ]; then
  # The initial secret is generated once at install. If the admin password has
  # since been changed, ArgoCD leaves this secret in place and stale, so say
  # when it was created and let the reader judge.
  created="$(kubectl_cp -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
    -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || true)"
  changed="$(kubectl_cp -n "$ARGOCD_NAMESPACE" get secret argocd-secret \
    -o go-template='{{index .data "admin.passwordMtime" | base64decode}}' 2>/dev/null || true)"

  printf '  user:     admin\n'
  printf '  password: %s\n' "$password"
  printf '  issued:   %s\n' "${created:-unknown}"

  if [ -n "$changed" ] && [ -n "$created" ] && [[ "$changed" > "$created" ]]; then
    echo
    warn "the admin password was changed at $changed, after this secret was issued."
    warn "The password above is stale. Reset it with:"
    warn "  HASH=\$(htpasswd -nbBC 10 \"\" 'new-password' | tr -d ':\\n' | sed 's/^\\\$2y/\\\$2a/')"
    warn "  kubectl -n $ARGOCD_NAMESPACE patch secret argocd-secret -p \\"
    warn "    \"{\\\"stringData\\\":{\\\"admin.password\\\":\\\"\$HASH\\\",\\\"admin.passwordMtime\\\":\\\"\$(date -u +%Y-%m-%dT%H:%M:%SZ)\\\"}}\""
    warn "  kubectl -n $ARGOCD_NAMESPACE rollout restart deploy/argocd-server"
  fi
else
  warn "argocd-initial-admin-secret is not there."
  warn "Either the admin password was already changed, or ArgoCD is not installed."
  warn "Run ./scripts/bootstrap-argocd.sh, or reset the password as described in the runbook."
fi

cat <<EOF

  URL:      http://localhost:$ARGOCD_LOCAL_PORT

server.insecure is set in gitops/bootstrap/argocd-values.yaml, so this is plain
HTTP over a loopback port-forward. http, not https.

Ctrl-C to stop the port-forward.

EOF

exec kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$ARGOCD_NAMESPACE" \
  port-forward svc/argocd-server "$ARGOCD_LOCAL_PORT:80"
