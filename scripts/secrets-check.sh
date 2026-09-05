#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

config=.sops.yaml
secret=secrets/proxmox.sops.yaml
age_key=${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -f "$config" ]] || die "$config is missing; run make secrets-init."
[[ -f "$age_key" ]] || die "age identity is missing; restore $age_key."
[[ -f "$secret" ]] || die "$secret is missing; run make secrets-init."
[[ "$(sops filestatus "$secret")" == '{"encrypted":true}' ]] || die "$secret is not SOPS-encrypted."
sops decrypt "$secret" >/dev/null || die "$secret is not decryptable with the current age identity."
sops exec-env "$secret" \
  'test -n "${TF_VAR_proxmox_api_token:-}" && test "$TF_VAR_proxmox_api_token" != CHANGE_ME' \
  >/dev/null || die 'Proxmox API token is missing or invalid.'

printf '%s\n' \
  'SOPS config:  ok' \
  'age identity: ok' \
  'proxmox:      decryptable'
