#!/usr/bin/env bash
set -euo pipefail

: "${PVE_SSH:?PVE_SSH is required}"

USER_ID="prometheus@pve"
TOKEN_ID="monitoring"
SOPS_FILE="secrets/monitoring.sops.yaml"

# Create service user if missing.
# USER_ID is intentionally expanded locally before being sent over SSH.
# shellcheck disable=SC2029
ssh "$PVE_SSH" "
  pveum user list | awk 'NR > 1 {print \$1}' | grep -qx '$USER_ID' ||
  pveum user add '$USER_ID' --comment 'Prometheus PVE Exporter'
"

# Ensure read-only permissions.
# shellcheck disable=SC2029
ssh "$PVE_SSH" \
  "pveum acl modify / \
    -user '$USER_ID' \
    -role PVEAuditor"

# Stop if token already exists.
# shellcheck disable=SC2029
if ssh "$PVE_SSH" \
  "pveum user token list '$USER_ID' --output-format json" |
  jq -e --arg token "$TOKEN_ID" \
    '.[] | select(.tokenid == $token)' >/dev/null
then
  echo "Monitoring token already exists: ${USER_ID}!${TOKEN_ID}"
  exit 0
fi

# Create token and capture one-time secret.
# shellcheck disable=SC2029
token_value="$(
  ssh "$PVE_SSH" \
    "pveum user token add '$USER_ID' '$TOKEN_ID' \
      -privsep 0 \
      --output-format json" |
  jq -er '.value'
)"

# Write directly into encrypted SOPS file.
printf '%s' "$token_value" |
  jq -Rs . |
  sops set --value-stdin \
    "$SOPS_FILE" \
    '["PVE_MONITORING_TOKEN_VALUE"]'

unset token_value

echo "Monitoring bootstrap completed."
echo "Identity: ${USER_ID}!${TOKEN_ID}"
echo "Secret stored in: ${SOPS_FILE}"
