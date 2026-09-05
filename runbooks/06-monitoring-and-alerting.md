# Monitoring / ntfy

Alert path:

```text
Prometheus -> Alertmanager -> ntfy.demo.svc.cluster.local -> homelab-alerts
```

`Watchdog` intentionally goes to the null receiver.

## Basic health

```bash
kubectl -n monitoring get pods,svc,servicemonitor,prometheusrule
kubectl -n demo get pods | grep ntfy
```

Local UIs when needed:

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093
```

The useful order is: metric exists -> alert fires -> Alertmanager routes it.

## PVE exporter

```bash
kubectl -n monitoring get deploy,svc,pods | grep pve
kubectl -n monitoring logs deploy/pve-exporter --tail=200
ssh "$PVE_SSH" "pveum user list | grep prometheus@pve"
ssh "$PVE_SSH" "pveum user token list prometheus@pve"
```

The monitoring user should exist with read-only `PVEAuditor` access.

If the user/CA bootstrap is missing:

```bash
make monitoring-bootstrap
```

Proxmox only shows a token secret when it is created. Recreating it means resealing
`gitops/platform/monitoring/pve-exporter-credentials.yml`.

## Alert fires, ntfy gets nothing

```bash
kubectl -n demo get deploy,svc,pods | grep ntfy
kubectl -n demo logs deploy/ntfy --tail=200
```

Test ntfy without Alertmanager:

```bash
kubectl -n demo run ntfy-test --rm -i --restart=Never \
  --image=curlimages/curl -- \
  curl -fsS -d 'manual homelab test' \
  http://ntfy.demo.svc.cluster.local/homelab-alerts
```

If this works, the remaining path is Prometheus/Alertmanager configuration.
