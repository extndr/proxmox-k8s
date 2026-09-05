# Back after a break

## Workstation

```bash
mise install
set -a; source .env; set +a
export KUBECONFIG="$PWD/.kube/config"
make secrets
```

If `make secrets` fails, go to [secrets / rebuild recovery](07-secrets-and-recovery.md).

## Network before Kubernetes

```bash
ip route get 10.10.10.1
ping -c 2 192.168.0.122
ping -c 2 10.10.10.1
```

If this path is broken, use [Proxmox host / lab network](00-proxmox-host-network.md).
Do not start with kubelet or Calico.

## Proxmox

```bash
ssh "$PVE_SSH" 'qm list'
make plan
```

Expected VMs:

```text
k8s-cp01
k8s-w01
k8s-w02
```

If they do not exist, use [build / reset / rebuild](02-cluster-build-rebuild.md).
If Terraform wants to replace/delete something unexpectedly, stop there and inspect
the plan before touching Kubernetes.

## Can I reach the nodes?

```bash
./scripts/inventory.sh
ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg" \
  ansible all -i ansible/inventory/hosts.json -m ping
```

No SSH -> stay below Kubernetes and fix VM/network/SSH first.

## Cluster

If `.kube/config` is present:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

If kubeconfig is missing but the VMs are still the existing cluster:

```bash
make configure
export KUBECONFIG="$PWD/.kube/config"
```

`NotReady` -> [node NotReady](03-node-not-ready.md).

## GitOps

```bash
kubectl -n argocd get applications
```

If Argo CD itself is missing:

```bash
make argocd
```

OutOfSync/Degraded -> [Argo CD unhealthy](04-argocd-unhealthy.md).

## Smoke test

```bash
make verify
curl -fsS http://demo.lab.home.arpa/healthz
curl -fsS http://demo.lab.home.arpa/readyz
```

If `make verify` is clean but the hostname is unreachable, go to
[Gateway / MetalLB / DNS](05-networking-and-ingress.md).

Monitoring is last:

```bash
kubectl -n monitoring get pods
```

For Prometheus/ntfy/PVE exporter issues see
[monitoring / ntfy](06-monitoring-and-alerting.md).
