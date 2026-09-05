#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

inventory=ansible/inventory/hosts.json
mkdir -p "$(dirname "$inventory")"

tmp=$(mktemp "${inventory}.XXXXXX")
trap 'rm -f "$tmp"' EXIT

terraform -chdir=terraform output -json ansible_inventory > "$tmp"
mv "$tmp" "$inventory"
trap - EXIT
