# GitOps

## Workloads

Workloads under this directory are automatically reconciled by the `workloads` ApplicationSet:

```text
gitops/workloads/<name>/
```

Removing a directory from `gitops/workloads/` removes its generated Argo CD Application and prunes the resources managed by that Application. Move disposable or on-demand manifests to `gitops/examples/` instead of leaving them under automatic reconciliation.

## Examples

Optional lab examples are kept outside the ApplicationSet and are not deployed automatically:

```text
gitops/examples/<name>/
```

Render or apply an example explicitly when needed, for example:

```bash
kubectl kustomize gitops/examples/podinfo
kubectl apply -k gitops/examples/podinfo
```

## Platform

```text
gitops/platform/
gitops/argocd/applications/
```

`demo-gateway` exposes one shared HTTP listener for `*.lab.home.arpa`. Each workload owns its precise hostname in its `HTTPRoute`, so adding a workload under that domain does not require editing the central Gateway.

## Commands

```bash
make secrets-apply
make install-argocd
make verify

kubectl --kubeconfig .kube/config -n argocd get applications
kubectl --kubeconfig .kube/config -n argocd get applicationsets
kubectl --kubeconfig .kube/config -n argocd describe application <app>
kubectl --kubeconfig .kube/config get events -A --sort-by=.lastTimestamp | tail -n 50
```
