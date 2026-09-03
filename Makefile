SHELL := /bin/bash
# Fail recipes on command errors, unset shell variables, and failed pipelines.
.SHELLFLAGS := -eu -o pipefail -c

.DEFAULT_GOAL := help

# Infrastructure operations are stateful and must run sequentially, even with make -j.
.NOTPARALLEL:

TF_DIR := terraform
ANSIBLE_DIR := ansible
ARGOCD_DIR := gitops/argocd
ARGOCD_INSTALL_DIR := $(ARGOCD_DIR)/install
ENV_FILE := .env

# .env contains local workstation/Proxmox workflow settings.
ifneq ($(wildcard $(ENV_FILE)),)
include $(ENV_FILE)
export PVE_SSH
export ANSIBLE_PRIVATE_KEY_FILE
export TF_VAR_proxmox_endpoint
export TF_VAR_proxmox_insecure
export TF_VAR_proxmox_node
export TF_VAR_template_vm_id
export TF_VAR_vm_datastore
export TF_VAR_network_bridge
endif

INVENTORY_DIR := $(ANSIBLE_DIR)/inventory
INVENTORY := $(INVENTORY_DIR)/hosts.json
KUBECONFIG_FILE := $(CURDIR)/.kube/config
SOPS_AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt
export SOPS_AGE_KEY_FILE
PROXMOX_SECRET := secrets/proxmox.sops.yaml

.PHONY: help secrets secrets-init secrets-edit template fmt lint validate test scan tf-init plan infra inventory configure install-argocd verify up reset destroy clean

help:
	@printf '%s\n' \
	  'Development:' \
	  '  make fmt                 - format tracked Terraform files' \
	  '  make lint                - lint repository source files' \
	  '  make validate            - validate Terraform and render GitOps configuration' \
	  '  make test                - run Terraform tests' \
	  '  make scan                - scan repository files for secrets and IaC misconfigurations' \
	  '' \
	  'Secrets:' \
	  '  make secrets             - check encrypted secrets and local SOPS access' \
	  '  make secrets-init        - create the local age identity and SOPS config' \
	  '  make secrets-edit NAME=x - edit one encrypted secret' \
	  '' \
	  'Argo CD:' \
	  '  make install-argocd      - install/recover Argo CD and seed the root Application' \
	  '  make argocd-password     - show the initial admin password' \
	  '  make argocd-forward      - forward the UI to https://localhost:8080' \
	  '' \
	  'Lab:' \
	  '  make template            - create the reusable Ubuntu cloud-init template in Proxmox' \
	  '  make plan                - show the Terraform plan' \
	  '  make up                  - provision the complete GitOps lab and verify it' \
	  '  make verify              - verify cluster readiness and Argo reconciliation' \
	  '  make reset               - reset kubeadm/CNI state on the existing VMs' \
	  '  make destroy             - destroy Terraform-managed Kubernetes VMs' \
	  '  make clean               - remove generated local inventory and kubeconfig' \
	  ''

secrets:
	@test -f .sops.yaml || { echo 'ERROR: .sops.yaml is missing; run make secrets-init.' >&2; exit 1; }
	@test -f "$(SOPS_AGE_KEY_FILE)" || { echo 'ERROR: age identity is missing; restore $(SOPS_AGE_KEY_FILE).' >&2; exit 1; }
	@test -f "$(PROXMOX_SECRET)" || { echo 'ERROR: $(PROXMOX_SECRET) is missing; run make secrets-init.' >&2; exit 1; }
	@test "$$(sops filestatus "$(PROXMOX_SECRET)")" = '{"encrypted":true}' || { echo 'ERROR: $(PROXMOX_SECRET) is not SOPS-encrypted.' >&2; exit 1; }
	@sops exec-env "$(PROXMOX_SECRET)" 'test -n "$${TF_VAR_proxmox_api_token:-}" && test "$$TF_VAR_proxmox_api_token" != CHANGE_ME' >/dev/null || { echo 'ERROR: Proxmox API token is missing or not decryptable.' >&2; exit 1; }
	@printf '%s\n' 'SOPS config:  ok' 'age identity: ok' 'proxmox:      decryptable'

secrets-init:
	@SOPS_AGE_KEY_FILE="$(SOPS_AGE_KEY_FILE)" ./scripts/sops-init.sh

secrets-edit:
	@test -n "$(NAME)" || { echo 'ERROR: NAME is required, for example: make secrets-edit NAME=proxmox' >&2; exit 1; }
	@file="secrets/$(NAME).sops.yaml"; \
		test -f "$$file" || { echo "ERROR: $$file does not exist." >&2; exit 1; }; \
		exec sops "$$file"

# Template creation stays a one-time host prerequisite while the pinned
# bpg/proxmox 0.111.1 provider has the known first-apply import_from bug #3022.
# Avoid adding Terraform failure-recovery glue solely to work around it.
template:
	@./scripts/proxmox-template.sh \
		"$${PVE_SSH:-}" \
		"$${TF_VAR_proxmox_node:-}" \
		"$${TF_VAR_template_vm_id:-}" \
		"$${TF_VAR_vm_datastore:-}" \
		"$${TF_VAR_network_bridge:-}"

fmt:
	@git ls-files -z -- '$(TF_DIR)/*.tf' '$(TF_DIR)/*.tfvars' | \
		xargs -0 -r terraform fmt

lint:
	@git ls-files -z -- '$(TF_DIR)/*.tf' '$(TF_DIR)/*.tfvars' | \
		xargs -0 -r terraform fmt -check
	@ANSIBLE_CONFIG="$(CURDIR)/$(ANSIBLE_DIR)/ansible.cfg" ansible-lint "$(ANSIBLE_DIR)"
	@shellcheck scripts/*.sh
	@if [ -d secrets ]; then \
		bad="$$(find secrets -type f ! -name '*.sops.yaml' -print -quit)"; \
		test -z "$$bad" || { echo "ERROR: unencrypted file under secrets/: $$bad" >&2; exit 1; }; \
		while IFS= read -r -d '' file; do \
			test "$$(sops filestatus "$$file")" = '{"encrypted":true}' || { echo "ERROR: $$file is not SOPS-encrypted." >&2; exit 1; }; \
		done < <(find secrets -type f -name '*.sops.yaml' -print0); \
	fi

validate:
	@terraform -chdir="$(TF_DIR)" init -backend=false -input=false -lockfile=readonly >/dev/null
	@terraform -chdir="$(TF_DIR)" validate
	@while IFS= read -r -d '' file; do \
		kubectl kustomize "$$(dirname "$$file")" >/dev/null; \
	done < <(find gitops -type f -name kustomization.yml -print0)

test:
	@terraform -chdir="$(TF_DIR)" init -backend=false -input=false -lockfile=readonly >/dev/null
	@terraform -chdir="$(TF_DIR)" test

scan:
	@tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT; \
	git ls-files -z --cached --others --exclude-standard | \
		xargs -0 -r cp --parents -t "$$tmp" --; \
	trivy fs --scanners secret --exit-code 1 --no-progress "$$tmp"; \
	trivy fs --scanners misconfig --severity HIGH,CRITICAL --exit-code 1 --no-progress \
		--tf-exclude-downloaded-modules "$$tmp"

tf-init:
	@terraform -chdir="$(TF_DIR)" init

plan: tf-init
	@sops exec-env --same-process "$(PROXMOX_SECRET)" 'test -n "$${TF_VAR_proxmox_api_token:-}" && test "$$TF_VAR_proxmox_api_token" != CHANGE_ME || { echo "ERROR: run make secrets first" >&2; exit 1; }; exec terraform -chdir="$(TF_DIR)" plan'

infra: tf-init
	@sops exec-env --same-process "$(PROXMOX_SECRET)" 'test -n "$${TF_VAR_proxmox_api_token:-}" && test "$$TF_VAR_proxmox_api_token" != CHANGE_ME || { echo "ERROR: run make secrets first" >&2; exit 1; }; exec terraform -chdir="$(TF_DIR)" apply'

inventory:
	@mkdir -p "$(INVENTORY_DIR)"
	@tmp="$(INVENTORY).tmp"; \
	trap 'rm -f "$$tmp"' EXIT; \
	terraform -chdir="$(TF_DIR)" output -json ansible_inventory > "$$tmp"; \
	mv "$$tmp" "$(INVENTORY)"

configure: inventory
	@ANSIBLE_CONFIG="$(CURDIR)/$(ANSIBLE_DIR)/ansible.cfg" \
		ansible-playbook \
		-i "$(INVENTORY)" \
		"$(ANSIBLE_DIR)/site.yml"

# The install uses the official pinned manifest via Kustomize, 
# then seeds the single root Application from this repository.
install-argocd:
	@kubectl --kubeconfig "$(KUBECONFIG_FILE)" \
		apply --server-side=true --force-conflicts --field-manager=lab-bootstrap \
		-k "$(ARGOCD_INSTALL_DIR)"
	@kubectl --kubeconfig "$(KUBECONFIG_FILE)" wait \
		--for=condition=Established \
		crd/applications.argoproj.io \
		crd/appprojects.argoproj.io \
		--timeout=180s
	@kubectl --kubeconfig "$(KUBECONFIG_FILE)" \
		apply --server-side=true --field-manager=lab-bootstrap \
		-f "$(ARGOCD_DIR)/root-application.yml"

argocd-password:
	@kubectl --kubeconfig "$(KUBECONFIG_FILE)" \
		-n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d; echo

argocd-forward:
	@kubectl --kubeconfig "$(KUBECONFIG_FILE)" \
		-n argocd port-forward svc/argocd-server 8080:443

verify:
	@TF_DIR="$(TF_DIR)" KUBECONFIG="$(KUBECONFIG_FILE)" ./scripts/verify.sh

# Terraform creates VMs, Ansible configures Kubernetes, Argo CD is installed
# and seeded, then verification checks the stable running-lab invariants.
up: infra configure install-argocd verify

reset: inventory
	@ANSIBLE_CONFIG="$(CURDIR)/$(ANSIBLE_DIR)/ansible.cfg" \
		ansible-playbook \
		-i "$(INVENTORY)" \
		"$(ANSIBLE_DIR)/reset.yml"
	@rm -rf "$(CURDIR)/.kube"

destroy: tf-init
	@sops exec-env --same-process "$(PROXMOX_SECRET)" 'test -n "$${TF_VAR_proxmox_api_token:-}" && test "$$TF_VAR_proxmox_api_token" != CHANGE_ME || { echo "ERROR: run make secrets first" >&2; exit 1; }; exec terraform -chdir="$(TF_DIR)" destroy'
	@rm -rf "$(INVENTORY_DIR)" "$(CURDIR)/.kube"

clean:
	@rm -rf "$(INVENTORY_DIR)" "$(CURDIR)/.kube"
