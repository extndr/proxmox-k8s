# proxmox-k8s

## Setup

```bash
cp .env.example .env
set -a; source .env; set +a
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
mise install
```

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
