#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

export KUBECONFIG="$PWD/.kube/config"
[[ -f "$KUBECONFIG" ]] || {
  echo "ERROR: kubeconfig not found: $KUBECONFIG" >&2
  exit 1
}

kubectl apply --server-side=true --force-conflicts --field-manager=lab-bootstrap \
  -k gitops/argocd/install

kubectl wait \
  --for=condition=Established \
  crd/applications.argoproj.io \
  crd/appprojects.argoproj.io \
  --timeout=180s

kubectl apply --server-side=true --field-manager=lab-bootstrap \
  -f gitops/argocd/root-application.yml
