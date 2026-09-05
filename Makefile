SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

SOPS_AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt
export SOPS_AGE_KEY_FILE

# Local workstation/Proxmox settings. Make exports values consumed by the
# commands it launches; Terraform secrets remain in SOPS.
ifneq ($(wildcard .env),)
include .env
export PVE_SSH
export ANSIBLE_PRIVATE_KEY_FILE
export TF_VAR_proxmox_endpoint
export TF_VAR_proxmox_insecure
export TF_VAR_proxmox_node
export TF_VAR_template_vm_id
export TF_VAR_vm_datastore
export TF_VAR_network_bridge
endif

.PHONY: help fmt check secrets secrets-init secrets-edit template plan infra configure argocd monitoring-bootstrap verify up reset destroy clean

help:
	@printf '%s\n' \
	  'Development:' \
	  '  make fmt                  - format Terraform files' \
	  '  make check                - run repository checks' \
	  '' \
	  'Secrets:' \
	  '  make secrets              - verify local SOPS access and Proxmox token' \
	  '  make secrets-init         - bootstrap local age/SOPS files' \
	  '  make secrets-edit         - edit the encrypted Proxmox token' \
	  '' \
	  'Bootstrap:' \
	  '  make template             - create/reuse the Proxmox Ubuntu template' \
	  '  make monitoring-bootstrap - bootstrap Proxmox monitoring identity/CA' \
	  '' \
	  'Lab:' \
	  '  make plan                 - show the Terraform plan' \
	  '  make infra                - apply Terraform infrastructure' \
	  '  make configure            - generate inventory and configure Kubernetes' \
	  '  make argocd               - install/recover Argo CD and seed GitOps' \
	  '  make up                   - run infra -> configure -> argocd -> verify' \
	  '  make verify               - verify cluster and Argo CD health' \
	  '  make reset                - reset kubeadm/CNI state on existing VMs' \
	  '  make destroy              - destroy Terraform-managed Kubernetes VMs' \
	  '  make clean                - remove generated inventory and kubeconfig'

fmt:
	@git ls-files -z -- 'terraform/*.tf' 'terraform/*.tfvars' | \
		xargs -0 -r terraform fmt

check:
	@./scripts/check.sh

secrets:
	@./scripts/secrets-check.sh

secrets-init:
	@./scripts/sops-init.sh

secrets-edit:
	@test -f secrets/proxmox.sops.yaml || { echo 'ERROR: secrets/proxmox.sops.yaml is missing; run make secrets-init.' >&2; exit 1; }
	@exec sops secrets/proxmox.sops.yaml

# One-time host prerequisite while the pinned bpg/proxmox provider has the
# known first-apply import_from bug. Existing templates are reused.
template:
	@./scripts/proxmox-template.sh \
		"$${PVE_SSH:-}" \
		"$${TF_VAR_proxmox_node:-}" \
		"$${TF_VAR_template_vm_id:-}" \
		"$${TF_VAR_vm_datastore:-}" \
		"$${TF_VAR_network_bridge:-}"

plan:
	@./scripts/secrets-check.sh >/dev/null
	@terraform -chdir=terraform init
	@sops exec-env --same-process secrets/proxmox.sops.yaml \
		'exec terraform -chdir=terraform plan'

infra:
	@./scripts/secrets-check.sh >/dev/null
	@terraform -chdir=terraform init
	@sops exec-env --same-process secrets/proxmox.sops.yaml \
		'exec terraform -chdir=terraform apply'

configure:
	@./scripts/inventory.sh
	@ANSIBLE_CONFIG="$(CURDIR)/ansible/ansible.cfg" \
		ansible-playbook -i ansible/inventory/hosts.json ansible/site.yml

argocd:
	@./scripts/argocd-bootstrap.sh

monitoring-bootstrap:
	@./scripts/monitoring-bootstrap.sh

verify:
	@./scripts/verify.sh

# Keep the lifecycle order explicit instead of encoding it as Make dependency
# semantics. Each step remains independently runnable for troubleshooting.
up:
	@$(MAKE) --no-print-directory infra
	@$(MAKE) --no-print-directory configure
	@$(MAKE) --no-print-directory argocd
	@$(MAKE) --no-print-directory verify

reset:
	@./scripts/inventory.sh
	@ANSIBLE_CONFIG="$(CURDIR)/ansible/ansible.cfg" \
		ansible-playbook -i ansible/inventory/hosts.json ansible/reset.yml
	@rm -rf "$(CURDIR)/.kube"

# Data on VM-local storage is destroyed with the VMs. See runbooks/08-postgres-data.md.
destroy:
	@./scripts/secrets-check.sh >/dev/null
	@terraform -chdir=terraform init
	@sops exec-env --same-process secrets/proxmox.sops.yaml \
		'exec terraform -chdir=terraform destroy'
	@$(MAKE) --no-print-directory clean

clean:
	@rm -rf ansible/inventory "$(CURDIR)/.kube"
