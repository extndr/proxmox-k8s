# Argo CD unhealthy

For `OutOfSync`, `Degraded`, or a failure in the Argo part of `make verify`.

```bash
kubectl -n argocd get applications
kubectl -n argocd describe application <app>
kubectl -n argocd get application <app> -o yaml
```

## OutOfSync

Compare the diff with `gitops/`. Fix Git if Git is wrong; do not `kubectl edit` a
GitOps-owned resource just to make the status green.

## Degraded / Missing / Unknown

Find the unhealthy resource, then debug that resource normally:

```bash
kubectl -n argocd get application <app> \
  -o jsonpath='{range .status.resources[*]}{.kind}{"\t"}{.namespace}{"\t"}{.name}{"\t"}{.health.status}{"\n"}{end}'

kubectl -n <namespace> get pods -o wide
kubectl -n <namespace> describe pod <pod>
kubectl -n <namespace> logs <pod> --all-containers --tail=200
```

Useful shortcuts for this repo:

- SealedSecret errors -> [secrets](07-secrets-and-recovery.md)
- image pull / old demo image -> [demo image path](09-ci-gitops-image.md)
- PostgreSQL/PVC -> [PostgreSQL data](08-postgres-data.md)
- Gateway endpoint -> [Gateway / MetalLB / DNS](05-networking-and-ingress.md)

If Argo CD itself is missing:

```bash
make argocd
```

After the fix:

```bash
kubectl -n argocd get applications
make verify
```
