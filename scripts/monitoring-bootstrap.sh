#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

: "${PVE_SSH:?PVE_SSH is required}"

USER_ID="prometheus@pve"
TOKEN_ID="monitoring"
export KUBECONFIG="$PWD/.kube/config"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

for command in ssh jq kubectl; do
  command -v "$command" >/dev/null 2>&1 || die "$command is required."
done

[[ -f "$KUBECONFIG" ]] || die "kubeconfig not found: $KUBECONFIG"

# Create the read-only Proxmox service identity if it does not already exist.
# USER_ID is intentionally expanded locally before being sent over SSH.
# shellcheck disable=SC2029
ssh "$PVE_SSH" "
  pveum user list | awk 'NR > 1 {print \$1}' | grep -qx '$USER_ID' ||
  pveum user add '$USER_ID' --comment 'Prometheus PVE Exporter'
"

# shellcheck disable=SC2029
ssh "$PVE_SSH" \
  "pveum acl modify / \
    -user '$USER_ID' \
    -role PVEAuditor"

# The Proxmox root CA is public trust material, not a secret. Keep the
# existing exporter setup reproducible without coupling it to secret handling.
kubectl create namespace monitoring --dry-run=client -o yaml | \
  kubectl apply --server-side=true \
    --field-manager=monitoring-bootstrap -f - >/dev/null

ssh "$PVE_SSH" cat /etc/pve/pve-root-ca.pem | \
  kubectl -n monitoring create configmap pve-ca \
    --from-file=pve-root-ca.pem=/dev/stdin \
    --dry-run=client -o yaml | \
  kubectl apply --server-side=true \
    --field-manager=monitoring-bootstrap -f - >/dev/null

# Existing tokens cannot be read back from Proxmox. If it already exists,
# the committed SealedSecret remains the source for the Kubernetes copy.
# shellcheck disable=SC2029
if ssh "$PVE_SSH" \
  "pveum user token list '$USER_ID' --output-format json" |
  jq -e --arg token "$TOKEN_ID" \
    '.[] | select(.tokenid == $token)' >/dev/null
then
  echo "Monitoring identity: ${USER_ID}!${TOKEN_ID}"
  echo "Proxmox CA ConfigMap: monitoring/pve-ca"
  echo "Monitoring token already exists; Kubernetes credentials stay managed by Sealed Secrets."
  exit 0
fi

# Proxmox returns the token secret only once. Do not persist it here: seal it
# with kubeseal and commit the resulting SealedSecret through the normal GitOps flow.
# shellcheck disable=SC2029
token_value="$(
  ssh "$PVE_SSH" \
    "pveum user token add '$USER_ID' '$TOKEN_ID' \
      -privsep 0 \
      --output-format json" |
  jq -er '.value'
)"

printf '%s\n' \
  "Monitoring identity created: ${USER_ID}!${TOKEN_ID}" \
  'The token value below is shown once by Proxmox. Seal it into' \
  'gitops/platform/monitoring/pve-exporter-credentials.yml before discarding it:' \
  "$token_value"
unset token_value
