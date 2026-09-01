#!/usr/bin/env bash
set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG must point at .kube/config}"
TF_DIR=${TF_DIR:-terraform}

echo '== Cluster =='
kubectl cluster-info
kubectl get nodes -o wide

mapfile -t expected_nodes < <(terraform -chdir="$TF_DIR" output -raw node_names)
mapfile -t actual_nodes < <(
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort
)

if [[ "${expected_nodes[*]}" != "${actual_nodes[*]}" ]]; then
  diff -u \
    <(printf '%s\n' "${expected_nodes[@]}") \
    <(printf '%s\n' "${actual_nodes[@]}") || true
  echo 'Kubernetes node set does not match Terraform-managed nodes.' >&2
  exit 1
fi

kubectl wait node --all --for=condition=Ready --timeout=180s
kubectl -n kube-system rollout status deployment/coredns --timeout=180s

echo '== Argo CD =='
root_application=lab
kubectl -n argocd wait "application/${root_application}" \
  --for=jsonpath='{.status.sync.status}'=Synced \
  --timeout=300s

mapfile -t application_sets < <(
  kubectl -n argocd get applicationsets.argoproj.io \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort
)

for appset in "${application_sets[@]}"; do
  kubectl -n argocd wait "applicationset/${appset}" \
    --for=jsonpath='{.status.conditions[?(@.type=="ResourcesUpToDate")].status}'=True \
    --timeout=300s
done

mapfile -t applications < <(
  kubectl -n argocd get applications.argoproj.io \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort
)

for app in "${applications[@]}"; do
  [[ "$app" == "$root_application" ]] && continue

  kubectl -n argocd wait "application/${app}" \
    --for=jsonpath='{.status.sync.status}'=Synced \
    --timeout=300s
  kubectl -n argocd wait "application/${app}" \
    --for=jsonpath='{.status.health.status}'=Healthy \
    --timeout=300s
done

kubectl -n argocd get applications.argoproj.io
echo 'Verification PASSED.'
