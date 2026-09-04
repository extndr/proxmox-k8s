# GitOps

## Workloads

Every directory under `gitops/workloads/` is a desired-state workload automatically reconciled by the `workloads` ApplicationSet:

```text
gitops/workloads/<name>/
```

The lab currently runs:

- `demo-app` — two-replica Go workload exposed through Gateway API.
- `postgres` — single-instance PostgreSQL dependency backed by `local-path` storage.
- `ntfy` — local notification service used by Alertmanager.

Removing a workload directory removes its generated Argo CD Application and prunes resources owned by that Application. Persistent data must therefore have an explicit lifecycle independent of disposable workload resources.

The demo application follows the GitOps image path:

```text
CI -> GHCR -> Git image digest update -> Argo CD -> Kubernetes -> worker containerd -> GHCR
```

Argo CD never pulls the container image itself. It reconciles the Deployment from Git; kubelet/containerd on the scheduled worker pulls the referenced image from GHCR.

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
