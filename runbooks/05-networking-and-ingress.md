# Gateway / MetalLB / DNS

The path is:

```text
client -> DNS -> route to 10.10.10.0/24 -> MetalLB -> Envoy Gateway
       -> HTTPRoute -> Service -> Pod
```

Work from the Pod outward. It is faster than staring at DNS first.

## Pod / Service

```bash
kubectl -n demo get pods,svc,endpointslices
kubectl -n demo get httproute
```

No Service endpoints -> workload/readiness issue, not MetalLB.

## Route / Gateway

```bash
kubectl -n demo get gateway demo-gateway -o wide
kubectl -n demo get httproute -o wide
kubectl get gatewayclass envoy-lab
kubectl get pods -A | grep -E 'envoy|gateway'
```

## MetalLB

```bash
kubectl -n metallb-system get pods
kubectl -n metallb-system get ipaddresspool,l2advertisement
kubectl get svc -A -o wide | grep LoadBalancer
```

Pool in this lab: `10.10.10.240-10.10.10.250`.

No external IP -> look at MetalLB controller/speaker logs before changing the pool.

## Bypass DNS

Get the Gateway LoadBalancer IP, then keep the Host header:

```bash
curl -v -H 'Host: demo.lab.home.arpa' http://<load-balancer-ip>/healthz
```

If that works, Kubernetes/Gateway is fine. The remaining problem is DNS or client
routing.

## DNS / LAN route

```bash
getent hosts demo.lab.home.arpa
getent hosts ntfy.lab.home.arpa
ip route get <load-balancer-ip>
```

On the workstation, the lab route should be:

```text
10.10.10.0/24 via 192.168.0.122
```

Works from Proxmox but not from the workstation -> check the workstation route first.
For other LAN clients, either add an equivalent route or configure it on the home router.

Final check:

```bash
curl -fsS http://demo.lab.home.arpa/healthz
curl -fsS http://demo.lab.home.arpa/readyz
curl -I http://ntfy.lab.home.arpa/
```
