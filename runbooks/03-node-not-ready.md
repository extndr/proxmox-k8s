# Node NotReady

Start by finding out whether this is a VM problem, kubelet/containerd problem, or CNI
problem. Do not reset the cluster before that is clear.

```bash
kubectl get nodes -o wide
kubectl describe node <node>
kubectl get events -A --sort-by=.lastTimestamp | tail -n 80
ssh "$PVE_SSH" 'qm list'
```

If the VM is stopped, fix that first.

## Node services

```bash
ssh ubuntu@<node-ip> 'hostname; uptime; df -h'
ssh ubuntu@<node-ip> 'sudo systemctl --no-pager --full status kubelet containerd'
ssh ubuntu@<node-ip> 'sudo journalctl -u kubelet -n 120 --no-pager'
ssh ubuntu@<node-ip> 'sudo journalctl -u containerd -n 120 --no-pager'
```

If one of them simply died:

```bash
ssh ubuntu@<node-ip> 'sudo systemctl restart containerd kubelet'
kubectl wait node/<node> --for=condition=Ready --timeout=180s
```

## Calico

```bash
kubectl get pods -n calico-system -o wide
kubectl get pods -n tigera-operator -o wide
kubectl get tigerastatus
kubectl get pods -A -o wide --field-selector spec.nodeName=<node>
```

Healthy kubelet + broken networking -> inspect the Calico pod on that node before
resetting anything.

## Pressure / full disk

```bash
kubectl describe node <node> | sed -n '/Conditions:/,/Addresses:/p'
ssh ubuntu@<node-ip> 'df -h'
```

Look for `DiskPressure`, `MemoryPressure`, `PIDPressure`, especially under
`/var/lib/containerd` and `/var/lib/kubelet`.

## Rebuilt/replaced node

Let the repo recreate the expected inventory/configuration:

```bash
make configure
make verify
```

## Last resort

If the VM is healthy but kubeadm state is no longer worth repairing:

```bash
make reset
make configure
make argocd
make verify
```

This resets the whole lab cluster, not one worker. Back up anything stateful first.
