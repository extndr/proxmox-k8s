# proxmox-k8s

## Setup

```bash
cp .env.example .env
set -a; source .env; set +a
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
mise install
make secrets-init
make secrets-edit NAME=proxmox
make secrets
```

The Proxmox API token is stored with SOPS. Keep the age identity outside the repository and back it up separately.

## Checks

```bash
make lint
make validate
make test
make scan
```

## Run

```bash
make template
make plan
make up
make verify
```

Step by step:

```bash
make infra
make configure
make install-argocd
```

## Reset

```bash
make reset
make destroy
make clean
```

GitOps: [`gitops/README.md`](gitops/README.md)
