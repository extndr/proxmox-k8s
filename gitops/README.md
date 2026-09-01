# GitOps

## Workloads

```text
gitops/apps/<name>/
```

Managed by the workloads ApplicationSet.

## Platform

```text
gitops/platform/
gitops/argocd/applications/
```

## Commands

```bash
make install-argocd
make verify

kubectl --kubeconfig .kube/config -n argocd get applications
kubectl --kubeconfig .kube/config -n argocd get applicationsets
kubectl --kubeconfig .kube/config -n argocd describe application <app>
kubectl --kubeconfig .kube/config get events -A --sort-by=.lastTimestamp | tail -n 50
```
