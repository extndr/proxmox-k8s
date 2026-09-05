# PostgreSQL data

PostgreSQL is one replica on `local-path`. The PVC can survive workload changes, but
the data still lives on one VM disk. `make destroy` destroys that disk too.

## Check it

```bash
kubectl -n demo get statefulset postgres
kubectl -n demo get pod -l app.kubernetes.io/name=postgres -o wide
kubectl -n demo get pvc
kubectl get pv -o wide
kubectl -n demo logs statefulset/postgres --tail=200
kubectl -n demo exec statefulset/postgres -- pg_isready -U lab -d lab
```

If the pod is `Pending`, inspect the PVC/PV and node placement before touching the
database itself.

## Backup before destroying VMs

```bash
mkdir -p backups
kubectl -n demo exec statefulset/postgres -- \
  pg_dump -U lab -d lab -Fc > backups/lab-$(date +%F-%H%M).dump
ls -lh backups/*.dump
```

For this lab a logical dump is enough; the important bit is that it ends up outside
the VMs.

## Restore

This uses `--clean`, so only do it when replacing the destination contents is intended.

```bash
cat backups/<backup>.dump | \
  kubectl -n demo exec -i statefulset/postgres -- \
  pg_restore -U lab -d lab --clean --if-exists

kubectl -n demo exec statefulset/postgres -- pg_isready -U lab -d lab
curl -fsS http://demo.lab.home.arpa/db
```

## PVC trouble

```bash
kubectl -n demo describe pod postgres-0
kubectl -n demo describe pvc
kubectl get storageclass local-path -o yaml
kubectl -n local-path-storage get pods
```

Do not delete the PVC/PV as the first troubleshooting step; with local-path it may be
the only reference left to the data.
