# Build / reset / rebuild

## Normal build

```bash
set -a; source .env; set +a
mise install
make secrets
make plan
make up
```

`make up` is the normal path:

```text
Terraform -> inventory/Ansible -> kubeadm/Calico -> Argo CD -> verify
```

If it fails, run the stages separately instead of guessing:

```bash
make infra
make configure
make argocd
make verify
```

## Reset Kubernetes, keep the VMs

```bash
make reset
make configure
make argocd
make verify
```

`make reset` resets kubeadm/CNI state and removes the local kubeconfig. Terraform VMs
stay in place.

I use this when the VM/network layer is fine and the Kubernetes state is not worth
repairing in place.

## Destroy and rebuild everything

Before this, check [secrets](07-secrets-and-recovery.md) and
[PostgreSQL data](08-postgres-data.md).

```bash
make destroy
make plan
make up
make monitoring-bootstrap
```

`make destroy` removes the VMs. Anything only on local VM disks is gone with them.

## Changes that mean rebuild

The Ansible control-plane role does not mutate these on an existing cluster:

- cluster name
- Pod CIDR
- Service CIDR
- control-plane endpoint

If one of them changes, rebuild instead of trying to force kubeadm into the new shape.
