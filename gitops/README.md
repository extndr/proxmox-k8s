# GitOps

## Workloads

Every directory under `gitops/workloads/` is a desired-state workload automatically reconciled by the `workloads` ApplicationSet:

```text
gitops/workloads/<name>/
```

Removing a workload directory removes its generated Argo CD Application and prunes resources owned by that Application. Persistent data must therefore have an explicit lifecycle independent of disposable workload resources.

The demo application follows the GitOps image path:

```text
CI -> delivery -> GHCR -> Git image digest update -> Argo CD -> Kubernetes -> worker containerd -> GHCR
```

CI verifies the change; delivery publishes the image and commits its immutable digest. Argo CD then reconciles the Deployment from Git, and kubelet/containerd on the scheduled worker pulls the referenced image from GHCR.

## Platform

```text
gitops/platform/
gitops/argocd/applications/
```

`demo-gateway` exposes one shared HTTP listener for `*.lab.home.arpa`. Each workload owns its precise hostname in its `HTTPRoute`, so adding a workload under that domain does not require editing the central Gateway.

Kubernetes runtime credentials are committed as `SealedSecret` resources. Argo CD applies those resources and the Sealed Secrets controller reconciles the corresponding native Kubernetes `Secret` objects. SOPS is reserved for bootstrap credentials consumed outside Kubernetes.

## Commands

```bash
make argocd
make verify

kubectl --kubeconfig .kube/config get sealedsecrets -A
kubectl --kubeconfig .kube/config -n argocd get applications
kubectl --kubeconfig .kube/config -n argocd get applicationsets
kubectl --kubeconfig .kube/config -n argocd describe application <app>
kubectl --kubeconfig .kube/config get events -A --sort-by=.lastTimestamp | tail -n 50
```
