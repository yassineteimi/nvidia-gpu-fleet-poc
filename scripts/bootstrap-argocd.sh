#!/usr/bin/env bash
#
# Install ArgoCD and hand it this repository. Run once, after cluster-up.sh.
#
# This is the only Helm release installed by a person. Everything else in the
# cluster, including the GPU Operator that owns the NVIDIA driver, arrives
# through the app of apps that this script applies at the end.
#

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_tools kubectl helm
require_kubeconfig

ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.9.2}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

log "adding the argo helm repository"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null

log "installing argo-cd $ARGOCD_CHART_VERSION into $ARGOCD_NAMESPACE"
KUBECONFIG="$KUBECONFIG_PATH" helm upgrade --install argocd argo/argo-cd \
  --version "$ARGOCD_CHART_VERSION" \
  --namespace "$ARGOCD_NAMESPACE" \
  --create-namespace \
  --values "$REPO_ROOT/gitops/bootstrap/argocd-values.yaml" \
  --wait \
  --timeout 15m

log "applying the root Application"
kubectl_cp apply -f "$REPO_ROOT/gitops/bootstrap/root-app.yaml"

log "waiting for ArgoCD to report on the applications it now owns"
sleep 15
kubectl_cp -n "$ARGOCD_NAMESPACE" get applications.argoproj.io || true

cat <<EOF

ArgoCD is installed and pointed at gitops/apps in this repository.

The root Application syncs, in order:
  wave 0  node-feature-discovery
  wave 1  gpu-operator

Nothing NVIDIA is installed until a GPU node exists, so this will look idle
until you run make up.

Open the UI with:

  make argocd-ui

Note: the Applications under gitops/apps reference this repository on branch
main. If you are working on another branch, ArgoCD will sync main, not your
branch, until you change targetRevision or merge.

EOF
