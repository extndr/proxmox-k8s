#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

section() {
  printf '\n== %s ==\n' "$1"
}

section 'Format / lint'
git ls-files -z -- 'terraform/*.tf' 'terraform/*.tfvars' | \
  xargs -0 -r terraform fmt -check
ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg" ansible-lint ansible
shellcheck scripts/*.sh

if [[ -d secrets ]]; then
  bad=$(find secrets -type f ! -name '*.sops.yaml' -print -quit)
  [[ -z "$bad" ]] || {
    echo "ERROR: unencrypted file under secrets/: $bad" >&2
    exit 1
  }

  while IFS= read -r -d '' file; do
    [[ "$(sops filestatus "$file")" == '{"encrypted":true}' ]] || {
      echo "ERROR: $file is not SOPS-encrypted." >&2
      exit 1
    }
  done < <(find secrets -type f -name '*.sops.yaml' -print0)
fi

section 'Terraform / GitOps validation'
terraform -chdir=terraform init -backend=false -input=false -lockfile=readonly >/dev/null
terraform -chdir=terraform validate

while IFS= read -r -d '' file; do
  kustomize build "$(dirname "$file")" >/dev/null
done < <(find gitops -type f -name kustomization.yml -print0)

section 'Terraform tests'
terraform -chdir=terraform test

section 'Security scan'
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git ls-files -z --cached --others --exclude-standard | \
  xargs -0 -r cp --parents -t "$tmp" --
trivy fs --scanners secret --exit-code 1 --no-progress "$tmp"
trivy fs --scanners misconfig --severity HIGH,CRITICAL --exit-code 1 --no-progress \
  --tf-exclude-downloaded-modules "$tmp"
