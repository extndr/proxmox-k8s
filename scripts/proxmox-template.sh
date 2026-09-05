#!/usr/bin/env bash
set -euo pipefail

# Proxmox template creation stays outside Terraform while the pinned
# bpg/proxmox 0.111.1 provider has the known first-apply import_from bug.
# The template is treated as a reusable host prerequisite/cache: if the VMID
# already contains a template, reuse it; recreate it manually when a new base
# image is desired.

usage() {
  cat <<'USAGE'
Usage:
  proxmox-template.sh <ssh-target> <proxmox-node> <template-vmid> <storage> <bridge>

Example:
  ./scripts/proxmox-template.sh root@192.168.0.122 pve 9000 local-lvm vmbr0

Creates the pinned Ubuntu 24.04 cloud-init template used by Terraform.
An existing template at the requested VMID is reused as-is.
USAGE
}

[[ ${1:-} == "-h" || ${1:-} == "--help" ]] && { usage; exit 0; }
[[ $# -eq 5 ]] || { usage >&2; exit 2; }

ssh_target=$1
proxmox_node=$2
template_vmid=$3
storage=$4
bridge=$5

for value in "$ssh_target" "$proxmox_node" "$template_vmid" "$storage" "$bridge"; do
  [[ -n "$value" ]] || {
    echo 'ERROR: template parameters must not be empty. Check .env.' >&2
    exit 2
  }
done

image_url="https://cloud-images.ubuntu.com/releases/noble/release-20260826/ubuntu-24.04-server-cloudimg-amd64.img"
image_sha256="d0fe84bb5f80853425fa6be28e2c106f30104c3cfe8611933f2e65c9b63f0e30"
template_name="ubuntu-2404-cloudinit"

printf 'Preparing Proxmox template %s (%s) on %s...\n' "$template_name" "$template_vmid" "$proxmox_node"

ssh "$ssh_target" bash -s -- \
  "$proxmox_node" "$template_vmid" "$storage" "$bridge" \
  "$image_url" "$image_sha256" "$template_name" <<'REMOTE'
set -euo pipefail

expected_node=$1
vmid=$2
storage=$3
bridge=$4
image_url=$5
image_sha256=$6
template_name=$7

if [[ "$(hostname -s)" != "$expected_node" ]]; then
  echo "ERROR: SSH target is not Proxmox node '$expected_node'." >&2
  exit 1
fi

config_value() {
  awk -F': ' -v wanted="$2" '$1 == wanted {print $2; exit}' <<<"$1"
}

if qm status "$vmid" >/dev/null 2>&1; then
  config=$(qm config "$vmid")
  if [[ "$(config_value "$config" template)" != "1" ]]; then
    echo "ERROR: VMID $vmid already exists and is not a template." >&2
    exit 1
  fi

  echo "Template VMID $vmid already exists; reusing it."
  exit 0
fi

pvesm status --storage "$storage" >/dev/null
ip link show "$bridge" >/dev/null

workdir=$(mktemp -d /tmp/lab-template.XXXXXX)
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 --connect-timeout 15 "$image_url" -o ubuntu.img
elif command -v wget >/dev/null 2>&1; then
  wget -O ubuntu.img "$image_url"
else
  echo 'ERROR: curl or wget is required on the Proxmox node.' >&2
  exit 1
fi

echo "${image_sha256}  ubuntu.img" | sha256sum --check --strict

created=0
rollback() {
  if [[ "$created" == "1" ]] && qm status "$vmid" >/dev/null 2>&1; then
    echo "Template build failed; deleting incomplete VMID $vmid..." >&2
    qm stop "$vmid" >/dev/null 2>&1 || true
    qm destroy "$vmid" --purge 1 >/dev/null 2>&1 || true
  fi
}
trap rollback ERR

qm create "$vmid" \
  --name "$template_name" \
  --ostype l26 \
  --memory 2048 \
  --cores 2 \
  --cpu host \
  --scsihw virtio-scsi-pci \
  --net0 "virtio,bridge=${bridge}" \
  --serial0 socket \
  --vga serial0
created=1

qm disk import "$vmid" "$workdir/ubuntu.img" "$storage"
imported_vol=$(qm config "$vmid" | awk -F': ' '/^unused0:/{print $2; exit}')
[[ -n "$imported_vol" ]] || { echo 'ERROR: image import did not create unused0.' >&2; exit 1; }

qm set "$vmid" --scsi0 "${imported_vol},discard=on"
qm set "$vmid" --boot order=scsi0
qm resize "$vmid" scsi0 12G
qm set "$vmid" --ide2 "${storage}:cloudinit"
qm set "$vmid" --ipconfig0 ip=dhcp
qm set "$vmid" --ciuser ubuntu
qm template "$vmid"

created=0
trap - ERR

echo "Template ready: VMID=$vmid name=$template_name"
REMOTE
