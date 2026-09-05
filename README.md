# proxmox-k8s

Personal Kubernetes lab on a single Proxmox host.

The repository starts at the VM layer. Proxmox host networking, the home-router DHCP
reservation, and Proxmox API identities are host prerequisites and are not managed by
Terraform.

## Ownership

```text
home router / Proxmox host  -> Wi-Fi uplink, vmbr0, routing/NAT, PVE users/tokens
Terraform                   -> Kubernetes VMs and their addresses
Ansible                     -> kubeadm, containerd, Kubernetes packages, Calico
Argo CD                     -> long-lived Kubernetes state under gitops/
```

That boundary matters during recovery: if `10.10.10.0/24` is unreachable, fix the
host/network layer before debugging Kubernetes.

## Network

The Proxmox machine has no wired uplink. It joins the home LAN over a USB Wi-Fi adapter
and routes a private VM network behind `vmbr0`.

```text
home LAN 192.168.0.0/24

workstation
    |
    | route 10.10.10.0/24 via 192.168.0.122
    |
    +---- Proxmox Wi-Fi 192.168.0.122
              |
              | routing / NAT
              |
           vmbr0 10.10.10.1/24
              |
              +-- k8s-cp01 10.10.10.50
              +-- k8s-w01  10.10.10.51
              +-- k8s-w02  10.10.10.52
```

The home router reserves `192.168.0.122` for the Proxmox Wi-Fi adapter. The adapter
MAC and SSID are host/router-local details and are intentionally not documented here.

The workstation has a route for `10.10.10.0/24` via `192.168.0.122`. Other LAN clients
need an equivalent route. Putting the route on the home router instead would make the
lab subnet reachable LAN-wide without per-device routes.

Kubernetes network ranges:

```text
Pod CIDR:      10.244.0.0/16
Service CIDR:  10.96.0.0/12
MetalLB pool:  10.10.10.240-10.10.10.250
Hostnames:     *.lab.home.arpa
```

## Proxmox host prerequisites

`vmbr0` is a routed bridge with no physical bridge port. The Wi-Fi adapter remains a
normal DHCP client; Proxmox forwards between the home LAN and the VM network and
masquerades VM traffic going to the Internet.

The relevant `/etc/network/interfaces` shape is below. The example uses `wlan0`;
replace it with the host's actual Wi-Fi interface. Wi-Fi authentication stays local to
the host and is not tracked in this repository.

```ini
auto lo
iface lo inet loopback

iface nic0 inet manual

auto wlan0
iface wlan0 inet dhcp
        # Wi-Fi authentication is configured locally on the host.

auto vmbr0
iface vmbr0 inet static
        address 10.10.10.1/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0

        # VM -> Internet, but keep home-LAN traffic routed without NAT.
        post-up iptables -t nat -A POSTROUTING -s 10.10.10.0/24 ! -d 192.168.0.0/24 -o wlan0 -j MASQUERADE
        post-down iptables -t nat -D POSTROUTING -s 10.10.10.0/24 ! -d 192.168.0.0/24 -o wlan0 -j MASQUERADE

        post-up iptables -A FORWARD -i vmbr0 -o wlan0 -s 10.10.10.0/24 -j ACCEPT
        post-down iptables -D FORWARD -i vmbr0 -o wlan0 -s 10.10.10.0/24 -j ACCEPT

        post-up iptables -A FORWARD -i wlan0 -o vmbr0 -s 192.168.0.0/24 -d 10.10.10.0/24 -j ACCEPT
        post-down iptables -D FORWARD -i wlan0 -o vmbr0 -s 192.168.0.0/24 -d 10.10.10.0/24 -j ACCEPT

        post-up iptables -A FORWARD -i wlan0 -o vmbr0 -d 10.10.10.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        post-down iptables -D FORWARD -i wlan0 -o vmbr0 -d 10.10.10.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

iface nic1 inet manual

source /etc/network/interfaces.d/*
```

IPv4 forwarding must also be enabled on the host:

```bash
sysctl net.ipv4.ip_forward
```

It should return `net.ipv4.ip_forward = 1`. On a rebuilt host, persist it with:

```bash
printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-homelab-router.conf
sysctl --system
```

The Proxmox API identities used by the lab are separated by purpose:

```text
terraform@pve    Terraform provisioning
prometheus@pve   PVE exporter (read-only)
```

Token values stay outside Git, while host ACLs remain a Proxmox prerequisite rather
than repository state. Monitoring uses `PVEAuditor`; Terraform should be scoped to the
permissions required by the provider instead of using `Administrator` as a default.

If this host state is missing or the lab subnet is unreachable, use
[`runbooks/00-proxmox-host-network.md`](runbooks/00-proxmox-host-network.md).

## Local setup

```bash
cp .env.example .env
set -a; source .env; set +a
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
mise install
make secrets-init
make secrets-edit
make secrets
```

The Proxmox API token used by Terraform is stored with SOPS. Keep the age identity
outside the repository and back it up separately.

Kubernetes runtime credentials are committed as `SealedSecret` resources. The Sealed
Secrets controller private key is recovery material and also lives outside Git.

## Run

Create/reuse the Proxmox Ubuntu template once, inspect the plan, then build the lab:

```bash
make template
make plan
make up
```

The stages can also be run separately:

```bash
make infra
make configure
make argocd
make verify
```

`make up` is just the explicit sequence:

```text
Terraform -> Ansible -> Argo CD -> verify
```

## Monitoring

Prometheus uses the dedicated `prometheus@pve` identity through the PVE exporter.
Bootstrap that external identity and the Proxmox CA after the cluster is reachable:

```bash
make monitoring-bootstrap
```

Alerts stay inside the lab:

```text
Prometheus -> Alertmanager -> ntfy.demo.svc.cluster.local -> homelab-alerts
```

The ntfy UI is exposed at `http://ntfy.lab.home.arpa`. A client still needs a route to
`10.10.10.0/24` to reach the MetalLB address.

## Demo workload

`demo-app/` is a small Go service used to exercise the cluster. It exposes `/healthz`,
`/readyz`, `/db`, and `/version`; PostgreSQL is its only runtime dependency.

CI publishes the image to GHCR, commits the immutable image digest
to `gitops/workloads/demo-app/kustomization.yml`, and Argo CD reconciles it. The GHCR
package is expected to be public, so the workers do not need an `imagePullSecret`.

The demo endpoint is `http://demo.lab.home.arpa`.

## Checks

```bash
make check
```

## Reset / destroy

```bash
make reset
make destroy
make clean
```

`make destroy` removes the Terraform-managed VMs. PostgreSQL uses VM-local storage, so
back up anything worth keeping first.

## Runbooks

[`runbooks/`](runbooks/README.md) contains troubleshooting and recovery procedures only.
Start with [`01-after-a-break.md`](runbooks/01-after-a-break.md) when returning to the
lab after time away.

GitOps layout: [`gitops/README.md`](gitops/README.md)
