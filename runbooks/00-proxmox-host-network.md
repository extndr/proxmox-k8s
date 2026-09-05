# Proxmox host / lab network

Use this before touching Kubernetes when the PVE API, SSH, `10.10.10.1`, or the VMs are
not reachable.

The normal network layout is documented in the repository [README](../README.md#network).

## From the workstation

```bash
ip route get 10.10.10.1
ping -c 2 192.168.0.122
ping -c 2 10.10.10.1
```

The route should go through `192.168.0.122` on the Wi-Fi interface. If it is missing:

```bash
sudo ip route add 10.10.10.0/24 via 192.168.0.122 dev wlan0
```

Interpret the first failure, not the last one:

```text
192.168.0.122 unreachable -> home Wi-Fi / PVE uplink
192.168.0.122 works, 10.10.10.1 fails -> forwarding / vmbr0 / host firewall
10.10.10.1 works, VM fails -> VM state / VM NIC / vmbr0 side
VM works, kubectl fails -> move up to Kubernetes
```

## On Proxmox

```bash
ip -br addr
ip route
sysctl net.ipv4.ip_forward
```

The important addresses are:

```text
Wi-Fi uplink   192.168.0.122/24 (DHCP reservation)
vmbr0          10.10.10.1/24
```

If the Wi-Fi address is not `.122`, fix the DHCP reservation/lease before changing the
workstation route or anything in Kubernetes.

Check the forwarding and NAT rules loaded from `/etc/network/interfaces`:

```bash
iptables -t nat -S POSTROUTING
iptables -S FORWARD
```

For the intended rules, compare with the host prerequisite section in the
[README](../README.md#proxmox-host-prerequisites).

Do not reload the only Wi-Fi uplink over SSH unless there is another way back into the
host. Use the local console for network changes if possible.

## VMs

Once the host path is good:

```bash
qm list
ping -c 2 10.10.10.50
ping -c 2 10.10.10.51
ping -c 2 10.10.10.52
```

Stopped/missing VMs are a Terraform/build problem. Existing VMs that cannot be reached
are still a host/VM network problem; Kubernetes is not the first place to look.

## After reinstalling Proxmox

Restore the host prerequisites before running Terraform:

```text
[ ] Wi-Fi works and receives the reserved 192.168.0.122
[ ] vmbr0 is 10.10.10.1/24
[ ] net.ipv4.ip_forward = 1
[ ] NAT/FORWARD rules are present
[ ] workstation can reach 10.10.10.1
[ ] terraform@pve exists and a working API token is recoverable from SOPS
[ ] SSH from the workstation to PVE works
```

Check the Terraform identity with:

```bash
pveum user list | grep terraform@pve
pveum user token list terraform@pve
pveum acl list | grep terraform@pve
```

If it is gone after a PVE reinstall, recreate the identity and token:

```bash
pveum user add terraform@pve --comment 'Terraform homelab'
pveum user token add terraform@pve homelab -privsep 0
```

Restore the provisioning ACL separately. Do not grant `Administrator` as a recovery
shortcut; grant the permissions required by the provider and validate them with
`make plan`.

Proxmox shows the token secret once. Store the returned token value in the SOPS-managed
Terraform secret with `make secrets-edit`, then verify it with `make secrets`.

The monitoring identity can be recreated later with `make monitoring-bootstrap`; it is
not required to bring the cluster back.
