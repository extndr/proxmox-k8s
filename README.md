# proxmox-k8s

## Setup

```bash
cp .env.example .env
set -a; source .env; set +a
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
mise install
make secrets-init
make secrets-edit
make secrets
```

The Proxmox API token used by Terraform is stored with SOPS. Keep the age identity outside the repository and back it up separately.

Kubernetes runtime credentials are stored in Git as `SealedSecret` resources and reconciled by Argo CD through the Sealed Secrets controller. The controller private key is recovery material: back it up separately if you want committed SealedSecrets to remain decryptable after a complete cluster rebuild.

Alert notifications use a self-hosted ntfy server deployed by GitOps. Alertmanager posts its native webhook payload directly to the in-cluster Service:

```text
Alertmanager -> ntfy.demo.svc.cluster.local -> homelab-alerts
```

ntfy applies its built-in `alertmanager` webhook template, so no relay, custom formatter, hosted ntfy account, or notification token is required. `info`, `warning`, and `critical` alerts are delivered to ntfy, resolved notifications are enabled, and the always-firing `Watchdog` alert stays on the null receiver.

The ntfy UI is exposed through the existing Envoy Gateway at `http://ntfy.lab.home.arpa`. Point that hostname at the MetalLB address assigned to `demo-gateway`, then subscribe the phone app to the `homelab-alerts` topic on that server. LAN clients must also have a route to the MetalLB subnet; with the repository defaults, the router should route `10.10.10.0/24` via the Proxmox host (`192.168.0.122`) so phones do not need per-device static routes.

## Monitoring bootstrap

The Proxmox exporter uses a read-only `prometheus@pve!monitoring` API token and the Proxmox root CA. Bootstrap that external identity after the cluster is reachable:

```bash
make monitoring-bootstrap
```

The CA is public trust material and is materialized as the `monitoring/pve-ca` ConfigMap. Kubernetes credentials themselves are not written by the bootstrap script; they remain declarative `SealedSecret` resources under `gitops/`.

If the Proxmox monitoring token has to be created again, Proxmox exposes its secret value only once. Seal that value with the standard `kubectl create secret --dry-run=client | kubeseal` flow and update `gitops/platform/monitoring/pve-exporter-credentials.yml`.

## Demo workload

`demo-app/` is a minimal Go service used to exercise the cluster rather than model application business logic. It exposes `/healthz`, `/readyz`, `/db`, and `/version`; PostgreSQL is its only runtime dependency.

The existing CI workflow builds the image and, on pushes to `main`, publishes it to `ghcr.io/extndr/proxmox-k8s-demo-app`, writes the resulting immutable digest into the Kustomize image definition in `gitops/workloads/demo-app/kustomization.yml`, and commits that desired-state change. Argo CD then reconciles Kubernetes; the worker selected by the scheduler pulls the image from GHCR.

After the first successful package publish, make the GHCR package public so the lab workers can pull it without an `imagePullSecret`. The PostgreSQL password is committed as the `postgres-credentials` SealedSecret under `gitops/workloads/postgres/`.

The demo endpoint is `http://demo.lab.home.arpa` once the hostname resolves to the shared Gateway address.

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
