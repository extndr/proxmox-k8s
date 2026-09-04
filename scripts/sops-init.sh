#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

config=.sops.yaml
secret=secrets/proxmox.sops.yaml
monitoring_secret=secrets/monitoring.sops.yaml
age_key=${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

for command in sops age-keygen openssl; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required; run mise install first."
done

if [[ ! -f "$age_key" ]]; then
  if [[ -f "$config" ]] || [[ -f "$secret" ]] || [[ -f "$monitoring_secret" ]]; then
    die "age identity is missing. Restore it instead of creating a new one."
  fi

  mkdir -p "$(dirname "$age_key")"
  umask 077
  age-keygen -o "$age_key"
fi
chmod 600 "$age_key"

if [[ ! -f "$config" ]]; then
  recipient=$(age-keygen -y "$age_key")
  cat > "$config" <<EOF_CONFIG
creation_rules:
  - path_regex: '^secrets/kubernetes/.*\\.sops\\.yaml$'
    encrypted_regex: '^(data|stringData)$'
    age: $recipient
  - path_regex: '^secrets/.*\\.sops\\.yaml$'
    age: $recipient
EOF_CONFIG
fi

if [[ ! -f "$secret" ]]; then
  mkdir -p "$(dirname "$secret")"
  tmp=$(mktemp "${secret}.XXXXXX")
  if ! printf '%s\n' \
    '# Format: USER@REALM!TOKENID=SECRET' \
    'TF_VAR_proxmox_api_token: CHANGE_ME' | \
    sops encrypt --filename-override "$secret" > "$tmp"; then
    rm -f "$tmp"
    exit 1
  fi
  mv "$tmp" "$secret"
fi

sops decrypt "$secret" >/dev/null || die "the current age identity cannot decrypt $secret."

if [[ ! -f "$monitoring_secret" ]]; then
  grafana_password=$(openssl rand -hex 24)
  tmp=$(mktemp "${monitoring_secret}.XXXXXX")
  if ! printf '%s\n' \
    "GRAFANA_ADMIN_PASSWORD: $grafana_password" \
    '# Secret value for prometheus@pve!monitoring.' \
    'PVE_MONITORING_TOKEN_VALUE: CHANGE_ME' | \
    sops encrypt --filename-override "$monitoring_secret" > "$tmp"; then
    rm -f "$tmp"
    exit 1
  fi
  mv "$tmp" "$monitoring_secret"
fi

sops decrypt "$monitoring_secret" >/dev/null || die "the current age identity cannot decrypt $monitoring_secret."

printf '%s\n' \
  "SOPS config:  $config" \
  "age identity: $age_key" \
  "secret:       $secret" \
  "monitoring:   $monitoring_secret" \
  'Next: make secrets-edit NAME=monitoring'
