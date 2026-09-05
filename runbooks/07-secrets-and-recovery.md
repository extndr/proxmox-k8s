# Secrets / rebuild recovery

There are two unrelated key systems in this lab. This is the part I do not want to
rediscover during a rebuild.

## SOPS / age

Terraform's Proxmox token is in:

```text
secrets/proxmox.sops.yaml
```

The age private key is outside Git, normally:

```text
~/.config/sops/age/keys.txt
```

Check access with:

```bash
make secrets
```

If the age key is lost, the existing SOPS file is not recoverable from the repo. Restore
the key from backup; creating a new age identity does not decrypt old ciphertext.

Useful commands:

```bash
make secrets-init
make secrets-edit
make secrets
```

## Sealed Secrets

These are encrypted for the controller key, not the SOPS age key. Examples:

```text
gitops/workloads/postgres/postgres-credentials.yml
gitops/platform/monitoring/pve-exporter-credentials.yml
gitops/platform/monitoring/grafana-admin.yml
```

Before a full cluster rebuild, save the controller key outside the repo:

```bash
recovery_dir="${XDG_DATA_HOME:-$HOME/.local/share}/proxmox-k8s/recovery"
install -d -m 700 "$recovery_dir"

kubectl -n kube-system get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > "$recovery_dir/sealed-secrets-controller-key.yaml"

chmod 600 "$recovery_dir/sealed-secrets-controller-key.yaml"
```

That file contains plaintext private-key material. Never write it under the repository
tree or commit it.

A fresh controller gets a fresh key. Without the old key, committed SealedSecrets need
to be resealed from plaintext sources.

## PVE monitoring token

Service account: `prometheus@pve`.

If it has to be recreated:

1. `make monitoring-bootstrap`
2. copy the one-time token secret
3. build a Secret locally with `kubectl create secret --dry-run=client`
4. pipe it through `kubeseal`
5. replace `gitops/platform/monitoring/pve-exporter-credentials.yml`
6. commit only the sealed output

## Before `make destroy`

Things that must be recoverable outside the cluster/VMs:

```text
[ ] SOPS age key
[ ] Proxmox Terraform token (or ability to recreate it)
[ ] Sealed Secrets controller key, or plaintext sources for resealing
[ ] PostgreSQL backup if I care about the current data
[ ] SSH private key
[ ] .env and terraform.tfvars
```
