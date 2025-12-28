###############################################################################
# Samakia Fabric – Makefile
# Purpose: Deterministic GitOps / IaaS / Compliance / Incident lifecycle
###############################################################################

.DEFAULT_GOAL := help
# Make does not support a SHELL with spaces; this is effectively `/usr/bin/env bash`.
SHELL := /usr/bin/env
.SHELLFLAGS := bash -euo pipefail -c

###############################################################################
# Repo root (absolute, stable regardless of where make is invoked from)
###############################################################################
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

###############################################################################
# Global variables (override via env or CLI)
###############################################################################

# Environments
ENV ?= samakia-prod
SRC_ENV ?= samakia-dev
DST_ENV ?= samakia-prod

# Paths (absolute by default for deterministic behavior)
PACKER_IMAGE_DIR ?= $(REPO_ROOT)/fabric-core/packer/lxc/ubuntu-24.04
PACKER_DIR ?= $(PACKER_IMAGE_DIR)
PACKER_SCRIPTS_DIR := $(REPO_ROOT)/fabric-core/packer/lxc/scripts
PACKER_TEMPLATE := packer.pkr.hcl
PACKER_ARTIFACT_GLOB ?= ubuntu-24.04-lxc-rootfs-v*.tar.gz
PACKER_ARTIFACT_PREFIX ?= ubuntu-24.04-lxc-rootfs-v

TERRAFORM_ENV_DIR := $(REPO_ROOT)/fabric-core/terraform/envs/$(ENV)
ANSIBLE_DIR := $(REPO_ROOT)/fabric-core/ansible

OPS_SCRIPTS_DIR := $(REPO_ROOT)/ops/scripts
FABRIC_CI_DIR := $(REPO_ROOT)/fabric-ci/scripts

# Optional inputs
IMAGE ?=
RELEASE_ID ?=
SNAPSHOT_DIR ?=
EVIDENCE_DIR ?=
PACK_SOURCES ?=
AUDIT_SOURCES ?=
INCIDENT_SOURCES ?=
INCIDENT_ID ?= incident-$(shell date -u +%Y%m%d-%H%M%S)
CORRELATION_ID ?= corr-$(shell date -u +%Y%m%d-%H%M%S)
PACK_NAME ?= compliance-pack-$(shell date -u +%Y%m%d-%H%M%S)
AUDIT_EXPORT_ID ?= audit-export-$(shell date -u +%Y%m%d-%H%M%S)
LEGAL_HOLD_ACTION ?= list
FORENSICS_FLAGS ?= --env $(ENV)
DOCTOR_FULL ?= 0

# Terraform flags
TF_INIT_FLAGS ?=
TF_PLAN_FLAGS ?=
TF_APPLY_FLAGS ?=

# Ansible flags
ANSIBLE_INVENTORY ?= inventory/terraform.py
ANSIBLE_BOOTSTRAP_KEYS_FILE ?= secrets/authorized_keys.yml
ANSIBLE_USER ?= samakia
ANSIBLE_FLAGS ?=

# Resolve override-friendly paths (absolute paths pass through unchanged)
ANSIBLE_INVENTORY_PATH := $(if $(filter /% ./% ../%,$(ANSIBLE_INVENTORY)),$(ANSIBLE_INVENTORY),$(ANSIBLE_DIR)/$(ANSIBLE_INVENTORY))
ANSIBLE_BOOTSTRAP_KEYS_PATH := $(if $(filter /% ./% ../%,$(ANSIBLE_BOOTSTRAP_KEYS_FILE)),$(ANSIBLE_BOOTSTRAP_KEYS_FILE),$(ANSIBLE_DIR)/$(ANSIBLE_BOOTSTRAP_KEYS_FILE))

# Compliance flags
COMPLIANCE_VERIFY_GLOB ?= $(REPO_ROOT)/compliance/$(ENV)/snapshot-*

###############################################################################
# Helpers
###############################################################################

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} \
		/^[a-zA-Z0-9_.-]+:.*##/ \
		{printf "\033[36m%-32s\033[0m %s\n", $$1, $$2}' \
		$(MAKEFILE_LIST)

###############################################################################
# Hygiene / Quality gates
###############################################################################

.PHONY: precommit
precommit: ## Run all pre-commit hooks (must pass before commit)
	pre-commit run --all-files

###############################################################################
# Golden image lifecycle (Packer)
###############################################################################

.PHONY: image.build
image.build: ## Build golden LXC image via Packer (uses Packer template defaults)
	@test -d "$(PACKER_IMAGE_DIR)" || (echo "ERROR: PACKER_IMAGE_DIR not found: $(PACKER_IMAGE_DIR)"; exit 1)
	@command -v packer >/dev/null 2>&1 || (echo "ERROR: packer not found in PATH"; exit 1)
	cd "$(PACKER_IMAGE_DIR)" && packer init . && packer validate . && packer build "$(PACKER_TEMPLATE)"

.PHONY: image.build-next
image.build-next: ## Build next image version v{max+1} (deterministic, no overwrite)
	@test -d "$(PACKER_IMAGE_DIR)" || (echo "ERROR: PACKER_IMAGE_DIR not found: $(PACKER_IMAGE_DIR)"; exit 1)
	@command -v packer >/dev/null 2>&1 || (echo "ERROR: packer not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		dir_abs="$$(cd "$(PACKER_IMAGE_DIR)" && pwd)"; \
		prefix="ubuntu-24.04-lxc-rootfs"; \
		# Robust max version discovery (no reliance on shell glob behavior) \
		max="$$(ls -1 "$$dir_abs/$${prefix}-v"*.tar.gz 2>/dev/null \
			| sed -E "s/.*-v([0-9]+)\\.tar\\.gz/\\1/" \
			| sort -n \
			| tail -n1)"; \
		if [[ -z "$$max" ]]; then max=0; fi; \
		next="$$((max+1))"; \
		fabric_version="v$${next}"; \
		artifact_basename="$${prefix}-v$${next}"; \
		out="$$dir_abs/$${artifact_basename}.tar.gz"; \
		if [[ -e "$$out" ]]; then \
			echo "ERROR: next artifact already exists (refusing to overwrite): $$out" >&2; \
			exit 1; \
		fi; \
		echo "Building $${artifact_basename} (fabric_version=$$fabric_version)"; \
		cd "$$dir_abs"; \
		packer init .; \
		packer validate .; \
		packer build -var "fabric_version=$$fabric_version" -var "artifact_basename=$$artifact_basename" "$(PACKER_TEMPLATE)"; \
		if [[ ! -f "$$out" ]]; then \
			echo "ERROR: build completed but artifact not found: $$out" >&2; \
			echo "Directory listing:" >&2; \
			ls -lah "$$dir_abs" >&2 || true; \
			exit 1; \
		fi; \
		echo "$$out" \
	'


.PHONY: image.list
image.list: ## List local image artifacts (filename, size, mtime)
	@test -d "$(PACKER_IMAGE_DIR)" || (echo "ERROR: PACKER_IMAGE_DIR not found: $(PACKER_IMAGE_DIR)"; exit 1)
	@bash -euo pipefail -c '\
		dir="$(PACKER_IMAGE_DIR)"; \
		dir_abs="$$(cd "$$dir" && pwd)"; \
		pattern="$(PACKER_ARTIFACT_GLOB)"; \
		shopt -s nullglob; \
		files=( "$$dir_abs"/$$pattern ); \
		if [[ "$${#files[@]}" -eq 0 ]]; then \
			echo "No artifacts found under $$dir_abs matching $$pattern"; \
			exit 0; \
		fi; \
		echo "FILENAME	SIZE_BYTES	MTIME_UTC"; \
		LC_ALL=C ls -1t "$$dir_abs"/$$pattern | while IFS= read -r f; do \
			base="$$(basename "$$f")"; \
			size="$$( (stat -c %s "$$f" 2>/dev/null || wc -c <"$$f") | tr -d " " )"; \
			epoch="$$(stat -c %Y "$$f" 2>/dev/null || stat -f %m "$$f" 2>/dev/null || echo 0)"; \
			if command -v date >/dev/null 2>&1 && date -u -d "@$$epoch" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then \
				ts="$$(date -u -d "@$$epoch" +%Y-%m-%dT%H:%M:%SZ)"; \
			else \
				ts="$$epoch"; \
			fi; \
			printf "%s\t%s\t%s\n" "$$base" "$$size" "$$ts"; \
		done \
	'

.PHONY: image.select
image.select: ## Interactive image picker (prints IMAGE=<absolute-path>; non-interactive: prints newest)
	@test -d "$(PACKER_IMAGE_DIR)" || (echo "ERROR: PACKER_IMAGE_DIR not found: $(PACKER_IMAGE_DIR)"; exit 1)
	@bash -euo pipefail -c '\
		dir="$(PACKER_IMAGE_DIR)"; \
		dir_abs="$$(cd "$$dir" && pwd)"; \
		shopt -s nullglob; \
		candidates=( "$$dir_abs"/$(PACKER_ARTIFACT_GLOB) ); \
		if [[ "$${#candidates[@]}" -eq 0 ]]; then \
			echo "ERROR: no images found under $$dir_abs matching $(PACKER_ARTIFACT_GLOB)" >&2; \
			exit 1; \
		fi; \
		if [[ ! -t 0 || ! -t 1 ]]; then \
			latest="$$(LC_ALL=C ls -1t "$$dir_abs"/$(PACKER_ARTIFACT_GLOB) 2>/dev/null | head -n 1)"; \
			echo "IMAGE=$$latest"; \
			exit 0; \
		fi; \
		pick=""; \
		if command -v fzf >/dev/null 2>&1; then \
			pick="$$(printf "%s\n" "$${candidates[@]}" | LC_ALL=C sort | fzf --prompt="Select image: " --height=15 --border)"; \
		elif command -v whiptail >/dev/null 2>&1; then \
			args=(); i=1; \
			for f in "$${candidates[@]}"; do args+=("$${i}" "$$(basename "$$f")"); i=$$((i+1)); done; \
			choice="$$(whiptail --title "Samakia Fabric" --menu "Select image" 20 90 10 "$${args[@]}" 3>&1 1>&2 2>&3 || true)"; \
			if [[ -n "$$choice" ]]; then pick="$${candidates[$$((choice-1))]}"; fi; \
		elif command -v dialog >/dev/null 2>&1; then \
			args=(); i=1; \
			for f in "$${candidates[@]}"; do args+=("$${i}" "$$(basename "$$f")"); i=$$((i+1)); done; \
			choice="$$(dialog --stdout --title "Samakia Fabric" --menu "Select image" 20 90 10 "$${args[@]}" || true)"; \
			if [[ -n "$$choice" ]]; then pick="$${candidates[$$((choice-1))]}"; fi; \
		else \
			echo "No fzf/whiptail/dialog; falling back to bash select (set IMAGE=... to avoid prompts)." >&2; \
			PS3="Select image: "; \
			{ select opt in "$${candidates[@]}"; do pick="$$opt"; break; done; } 1>&2; \
		fi; \
		if [[ -z "$$pick" ]]; then echo "ERROR: no image selected" >&2; exit 1; fi; \
		echo "IMAGE=$$pick" \
	'

.PHONY: image.upload
image.upload: ## Upload golden image to Proxmox via API (IMAGE=... or interactive)
	@test -d "$(PACKER_SCRIPTS_DIR)" || (echo "ERROR: PACKER_SCRIPTS_DIR not found: $(PACKER_SCRIPTS_DIR)"; exit 1)
	@test -x "$(PACKER_SCRIPTS_DIR)/upload-lxc-template-via-api.sh" || (echo "ERROR: upload script not executable: $(PACKER_SCRIPTS_DIR)/upload-lxc-template-via-api.sh"; exit 1)
	@command -v curl >/dev/null 2>&1 || (echo "ERROR: curl not found in PATH"; exit 1)
	@command -v python3 >/dev/null 2>&1 || (echo "ERROR: python3 not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		# Env contract: prefer PM_*; fallback to TF_VAR_* (no printing of secrets). \
		pm_url="$${PM_API_URL:-$${TF_VAR_pm_api_url:-}}"; \
		pm_id="$${PM_API_TOKEN_ID:-$${TF_VAR_pm_api_token_id:-}}"; \
		pm_secret="$${PM_API_TOKEN_SECRET:-$${TF_VAR_pm_api_token_secret:-}}"; \
		if [[ -z "$$pm_url" ]]; then echo "ERROR: missing Proxmox API URL. Set PM_API_URL (or TF_VAR_pm_api_url)." >&2; exit 1; fi; \
		if [[ -z "$$pm_id" ]]; then echo "ERROR: missing token id. Set PM_API_TOKEN_ID (or TF_VAR_pm_api_token_id)." >&2; exit 1; fi; \
		if [[ -z "$$pm_secret" ]]; then echo "ERROR: missing token secret. Set PM_API_TOKEN_SECRET (or TF_VAR_pm_api_token_secret)." >&2; exit 1; fi; \
		export PM_API_URL="$$pm_url" PM_API_TOKEN_ID="$$pm_id" PM_API_TOKEN_SECRET="$$pm_secret"; \
		image="$${IMAGE:-}"; \
		dir_abs="$$(cd "$(PACKER_IMAGE_DIR)" && pwd)"; \
		if [[ -z "$$image" ]]; then \
			if [[ ! -t 0 || ! -t 1 ]]; then \
				echo "ERROR: IMAGE is required in non-interactive mode (e.g. make image.upload IMAGE=...)" >&2; \
				exit 1; \
			fi; \
			shopt -s nullglob; \
			candidates=( "$$dir_abs"/$(PACKER_ARTIFACT_GLOB) ); \
			if [[ "$${#candidates[@]}" -eq 0 ]]; then candidates=( "$$dir_abs"/*.tar.gz ); fi; \
			if [[ "$${#candidates[@]}" -eq 0 ]]; then echo "ERROR: no .tar.gz images found under $$dir_abs" >&2; exit 1; fi; \
			if command -v fzf >/dev/null 2>&1; then \
				image="$$(printf "%s\n" "$${candidates[@]}" | LC_ALL=C sort | fzf --prompt="Select rootfs tar.gz to upload: " --height=15 --border)"; \
			elif command -v whiptail >/dev/null 2>&1; then \
				args=(); i=1; for f in "$${candidates[@]}"; do args+=("$${i}" "$$(basename "$$f")"); i=$$((i+1)); done; \
				choice="$$(whiptail --title "Samakia Fabric" --menu "Select rootfs tar.gz to upload" 20 90 10 "$${args[@]}" 3>&1 1>&2 2>&3 || true)"; \
				if [[ -n "$$choice" ]]; then image="$${candidates[$$((choice-1))]}"; fi; \
			elif command -v dialog >/dev/null 2>&1; then \
				args=(); i=1; for f in "$${candidates[@]}"; do args+=("$${i}" "$$(basename "$$f")"); i=$$((i+1)); done; \
				choice="$$(dialog --stdout --title "Samakia Fabric" --menu "Select rootfs tar.gz to upload" 20 90 10 "$${args[@]}" || true)"; \
				if [[ -n "$$choice" ]]; then image="$${candidates[$$((choice-1))]}"; fi; \
			else \
				echo "No fzf/whiptail/dialog; falling back to bash select (set IMAGE=... to avoid prompts)." >&2; \
				PS3="Select rootfs tar.gz to upload: "; \
				{ select opt in "$${candidates[@]}"; do image="$$opt"; break; done; } 1>&2; \
			fi; \
			if [[ -z "$$image" ]]; then echo "ERROR: no image selected" >&2; exit 1; fi; \
		fi; \
		# Resolve basename to dir_abs if needed \
		if [[ ! -f "$$image" ]]; then \
			if [[ "$$image" != */* && -f "$$dir_abs/$$image" ]]; then image="$$dir_abs/$$image"; fi; \
		fi; \
		if [[ ! -f "$$image" ]]; then echo "ERROR: IMAGE not found: $$image" >&2; exit 1; fi; \
		echo "Uploading rootfs: $$(basename "$$image")" >&2; \
		# IMPORTANT: uploader script expects positional path (not --file flag) \
		bash "$(PACKER_SCRIPTS_DIR)/upload-lxc-template-via-api.sh" "$$image" \
	'


.PHONY: image.build-upload
image.build-upload: ## Build next image version then upload (interactive select if TTY; else newest)
	@test -d "$(PACKER_IMAGE_DIR)" || (echo "ERROR: PACKER_IMAGE_DIR not found: $(PACKER_IMAGE_DIR)"; exit 1)
	@command -v packer >/dev/null 2>&1 || (echo "ERROR: packer not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		artifact="$$( $(MAKE) -s image.build-next )"; \
		image="$${IMAGE:-}"; \
		if [[ -z "$$image" ]]; then \
			if [[ -t 0 && -t 1 ]]; then \
				echo "Built: $$artifact" >&2; \
				picked="$$(IMAGE="" $(MAKE) -s image.select)"; \
				image="$${picked#IMAGE=}"; \
			else \
				image="$$artifact"; \
			fi; \
		fi; \
		$(MAKE) image.upload IMAGE="$$image" \
	'

.PHONY: image.promote
image.promote: ## Promote image version (GitOps-only: prints the exact pin to apply in Terraform)
	@bash -euo pipefail -c '\
		image="$${IMAGE:-}"; \
		if [[ -z "$$image" && -t 0 && -t 1 ]]; then \
			mapfile -t candidates < <(ls -1 "$(PACKER_DIR)"/ubuntu-24.04-lxc-rootfs-v*.tar.gz 2>/dev/null || true); \
			if [[ "$${#candidates[@]}" -eq 0 ]]; then \
				echo "ERROR: no versioned images found under $(PACKER_DIR) (expected ubuntu-24.04-lxc-rootfs-vN.tar.gz)" >&2; \
				exit 1; \
			fi; \
			if command -v fzf >/dev/null 2>&1; then \
				image="$$(printf "%s\n" "$${candidates[@]}" | fzf --prompt="Select image to promote (Git pin only): " --height=15 --border)"; \
			else \
				echo "fzf not found; falling back to numbered selection (set IMAGE=... to avoid prompts)." >&2; \
				PS3="Select image to promote: "; \
				{ select opt in "$${candidates[@]}"; do image="$$opt"; break; done; } 1>&2; \
			fi; \
		fi; \
		if [[ -z "$$image" ]]; then \
			echo "ERROR: set IMAGE=... (e.g. $(PACKER_DIR)/ubuntu-24.04-lxc-rootfs-v3.tar.gz) to compute a promotion pin" >&2; \
			exit 1; \
		fi; \
		base="$$(basename "$$image")"; \
		if [[ "$$base" =~ -v([0-9]+)\\.tar\\.gz$$ ]]; then \
			vnum="$${BASH_REMATCH[1]}"; \
			echo "Promote (Git change): set prod env to v$${vnum}"; \
			echo "Target env: $(DST_ENV)"; \
			echo "Edit: fabric-core/terraform/envs/$(DST_ENV)/main.tf"; \
			echo "Set:"; \
			echo "  lxc_rootfs_version = \"v$${vnum}\""; \
			echo "  lxc_template       = \"vztmpl/ubuntu-24.04-lxc-rootfs-v$${vnum}.tar.gz\""; \
		else \
			echo "ERROR: IMAGE basename does not look versioned (*-vN.tar.gz): $$base" >&2; \
			exit 1; \
		fi \
	'

###############################################################################
# Terraform lifecycle
###############################################################################

.PHONY: tf.init
tf.init: ## Terraform init for ENV
	@test -d "$(TERRAFORM_ENV_DIR)" || (echo "ERROR: Terraform env dir not found: $(TERRAFORM_ENV_DIR)"; exit 1)
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	terraform -chdir="$(TERRAFORM_ENV_DIR)" init $(TF_INIT_FLAGS)

.PHONY: tf.plan
tf.plan: ## Terraform plan for ENV
	@test -d "$(TERRAFORM_ENV_DIR)" || (echo "ERROR: Terraform env dir not found: $(TERRAFORM_ENV_DIR)"; exit 1)
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	terraform -chdir="$(TERRAFORM_ENV_DIR)" init $(TF_INIT_FLAGS) >/dev/null
	terraform -chdir="$(TERRAFORM_ENV_DIR)" validate
	terraform -chdir="$(TERRAFORM_ENV_DIR)" plan $(TF_PLAN_FLAGS)

.PHONY: tf.apply
tf.apply: ## Terraform apply for ENV
	@test -d "$(TERRAFORM_ENV_DIR)" || (echo "ERROR: Terraform env dir not found: $(TERRAFORM_ENV_DIR)"; exit 1)
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	terraform -chdir="$(TERRAFORM_ENV_DIR)" init $(TF_INIT_FLAGS) >/dev/null
	terraform -chdir="$(TERRAFORM_ENV_DIR)" validate
	terraform -chdir="$(TERRAFORM_ENV_DIR)" apply $(TF_APPLY_FLAGS)

###############################################################################
# Ansible lifecycle
###############################################################################

.PHONY: ansible.inventory
ansible.inventory: ## Show resolved Ansible inventory
	@test -d "$(ANSIBLE_DIR)" || (echo "ERROR: ANSIBLE_DIR not found: $(ANSIBLE_DIR)"; exit 1)
	@command -v ansible-inventory >/dev/null 2>&1 || (echo "ERROR: ansible-inventory not found in PATH"; exit 1)
	FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
		ansible-inventory -i "$(ANSIBLE_INVENTORY_PATH)" --list

.PHONY: ansible.bootstrap
ansible.bootstrap: ## Phase-1 bootstrap (root-only)
	@test -d "$(ANSIBLE_DIR)" || (echo "ERROR: ANSIBLE_DIR not found: $(ANSIBLE_DIR)"; exit 1)
	@command -v ansible-playbook >/dev/null 2>&1 || (echo "ERROR: ansible-playbook not found in PATH"; exit 1)
	@test -f "$(ANSIBLE_BOOTSTRAP_KEYS_PATH)" || ( \
		echo "ERROR: missing bootstrap keys file: $(ANSIBLE_BOOTSTRAP_KEYS_PATH)"; \
		echo "Create it (untracked) with: bootstrap_authorized_keys: [\"ssh-ed25519 ...\"]"; \
		exit 1 \
	)
	FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
		ansible-playbook -i "$(ANSIBLE_INVENTORY_PATH)" "$(ANSIBLE_DIR)/playbooks/bootstrap.yml" -u root -e @"$(ANSIBLE_BOOTSTRAP_KEYS_PATH)" $(ANSIBLE_FLAGS)

.PHONY: ansible.harden
ansible.harden: ## Phase-2 hardening (runs as samakia)
	@test -d "$(ANSIBLE_DIR)" || (echo "ERROR: ANSIBLE_DIR not found: $(ANSIBLE_DIR)"; exit 1)
	@command -v ansible-playbook >/dev/null 2>&1 || (echo "ERROR: ansible-playbook not found in PATH"; exit 1)
	FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
		ansible-playbook -i "$(ANSIBLE_INVENTORY_PATH)" "$(ANSIBLE_DIR)/playbooks/harden.yml" -u "$(ANSIBLE_USER)" $(ANSIBLE_FLAGS)

###############################################################################
# Drift / Compliance / Audit
###############################################################################

.PHONY: audit.drift
audit.drift: ## Read-only drift detection
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	@command -v ansible-playbook >/dev/null 2>&1 || (echo "ERROR: ansible-playbook not found in PATH"; exit 1)
	bash "$(OPS_SCRIPTS_DIR)/drift-audit.sh" "$(ENV)"

.PHONY: compliance.snapshot
compliance.snapshot: ## Create signed compliance snapshot
	bash "$(OPS_SCRIPTS_DIR)/compliance-snapshot.sh" "$(ENV)"

.PHONY: compliance.verify
compliance.verify: ## Verify compliance snapshot offline (SNAPSHOT_DIR=... or interactive)
	@bash -euo pipefail -c '\
		dir="$${SNAPSHOT_DIR:-}"; \
		if [[ -z "$$dir" ]]; then \
			if [[ ! -t 0 || ! -t 1 ]]; then \
				echo "ERROR: SNAPSHOT_DIR is required in non-interactive mode (e.g. make compliance.verify SNAPSHOT_DIR=...)" >&2; \
				exit 1; \
			fi; \
			mapfile -t candidates < <(ls -d $(COMPLIANCE_VERIFY_GLOB) 2>/dev/null | LC_ALL=C sort || true); \
			if [[ "$${#candidates[@]}" -eq 0 ]]; then echo "ERROR: no snapshots found matching: $(COMPLIANCE_VERIFY_GLOB)" >&2; exit 1; fi; \
			if command -v fzf >/dev/null 2>&1; then \
				dir="$$(printf "%s\n" "$${candidates[@]}" | fzf --prompt="Select snapshot to verify: " --height=15 --border)"; \
			elif command -v whiptail >/dev/null 2>&1; then \
				args=(); i=1; for d in "$${candidates[@]}"; do args+=("$${i}" "$$d"); i=$$((i+1)); done; \
				choice="$$(whiptail --title "Samakia Fabric" --menu "Select snapshot to verify" 20 90 10 "$${args[@]}" 3>&1 1>&2 2>&3 || true)"; \
				if [[ -n "$$choice" ]]; then dir="$${candidates[$$((choice-1))]}"; fi; \
			elif command -v dialog >/dev/null 2>&1; then \
				args=(); i=1; for d in "$${candidates[@]}"; do args+=("$${i}" "$$d"); i=$$((i+1)); done; \
				choice="$$(dialog --stdout --title "Samakia Fabric" --menu "Select snapshot to verify" 20 90 10 "$${args[@]}" || true)"; \
				if [[ -n "$$choice" ]]; then dir="$${candidates[$$((choice-1))]}"; fi; \
			else \
				echo "No fzf/whiptail/dialog; falling back to bash select (set SNAPSHOT_DIR=... to avoid prompts)." >&2; \
				PS3="Select snapshot to verify: "; { select opt in "$${candidates[@]}"; do dir="$$opt"; break; done; } 1>&2; \
			fi; \
			if [[ -z "$$dir" ]]; then echo "ERROR: no snapshot selected" >&2; exit 1; fi; \
		fi; \
		if [[ ! -d "$$dir" ]]; then echo "ERROR: SNAPSHOT_DIR not found: $$dir" >&2; exit 1; fi; \
		bash "$(OPS_SCRIPTS_DIR)/verify-compliance-snapshot.sh" "$$dir" \
	'

###############################################################################
# Compliance packing & export
###############################################################################

.PHONY: compliance.pack
compliance.pack: ## Bundle multiple evidence directories (PACK_SOURCES="dir1 dir2"; output under compliance/packs/)
	@test -n "$(PACK_SOURCES)" || (echo "ERROR: PACK_SOURCES is required (space-separated list of evidence directories)"; exit 1)
	@mkdir -p "$(REPO_ROOT)/compliance/packs/$(PACK_NAME)"
	@for d in $(PACK_SOURCES); do \
		test -e "$$d" || (echo "ERROR: source not found: $$d"; exit 1); \
		cp -a "$$d" "$(REPO_ROOT)/compliance/packs/$(PACK_NAME)/"; \
	done
	@echo "Pack created at $(REPO_ROOT)/compliance/packs/$(PACK_NAME)"

.PHONY: audit.export
audit.export: ## Export audit artifacts for external review
	@test -n "$(AUDIT_SOURCES)" || (echo "ERROR: AUDIT_SOURCES is required (space-separated list of directories/files)"; exit 1)
	@mkdir -p "$(REPO_ROOT)/audit/exports/$(AUDIT_EXPORT_ID)"
	@for d in $(AUDIT_SOURCES); do \
		test -e "$$d" || (echo "ERROR: source not found: $$d"; exit 1); \
		cp -a "$$d" "$(REPO_ROOT)/audit/exports/$(AUDIT_EXPORT_ID)/"; \
	done
	@cp -a "$(REPO_ROOT)/CHANGELOG.md" "$(REPO_ROOT)/audit/exports/$(AUDIT_EXPORT_ID)/"
	@echo "Audit export ready at $(REPO_ROOT)/audit/exports/$(AUDIT_EXPORT_ID)"

###############################################################################
# Legal hold / retention
###############################################################################

.PHONY: legal-hold
legal-hold: ## Manage legal-hold labels
	@bash -euo pipefail -c '\
		action="$(LEGAL_HOLD_ACTION)"; \
		case "$$action" in \
			list) bash "$(OPS_SCRIPTS_DIR)/legal-hold-manage.sh" list ;; \
			validate) : "$${EVIDENCE_DIR:?ERROR: set EVIDENCE_DIR}"; bash "$(OPS_SCRIPTS_DIR)/legal-hold-manage.sh" validate --path "$$EVIDENCE_DIR" ;; \
			require-dual-control) : "$${EVIDENCE_DIR:?ERROR: set EVIDENCE_DIR}"; \
				if [[ -n "$${GPG_KEYS:-}" ]]; then bash "$(OPS_SCRIPTS_DIR)/legal-hold-manage.sh" require-dual-control --path "$$EVIDENCE_DIR" --keys "$$GPG_KEYS"; \
				else bash "$(OPS_SCRIPTS_DIR)/legal-hold-manage.sh" require-dual-control --path "$$EVIDENCE_DIR"; fi ;; \
			declare) : "$${EVIDENCE_DIR:?ERROR: set EVIDENCE_DIR}"; : "$${HOLD_ID:?ERROR: set HOLD_ID}"; : "$${DECLARED_BY:?ERROR: set DECLARED_BY}"; : "$${HOLD_REASON:?ERROR: set HOLD_REASON}"; : "$${REVIEW_DATE:?ERROR: set REVIEW_DATE (YYYY-MM-DD)}"; \
				bash "$(OPS_SCRIPTS_DIR)/legal-hold-manage.sh" declare --path "$$EVIDENCE_DIR" --hold-id "$$HOLD_ID" --declared-by "$$DECLARED_BY" --reason "$$HOLD_REASON" --review-date "$$REVIEW_DATE" ;; \
			release) : "$${EVIDENCE_DIR:?ERROR: set EVIDENCE_DIR}"; : "$${RELEASED_BY:?ERROR: set RELEASED_BY}"; : "$${RELEASE_REASON:?ERROR: set RELEASE_REASON}"; \
				bash "$(OPS_SCRIPTS_DIR)/legal-hold-manage.sh" release --path "$$EVIDENCE_DIR" --released-by "$$RELEASED_BY" --reason "$$RELEASE_REASON" ;; \
			*) echo "ERROR: unknown LEGAL_HOLD_ACTION=$$action (use list|validate|declare|require-dual-control|release)" >&2; exit 2 ;; \
		esac \
	'

###############################################################################
# Incident response / forensics
###############################################################################

.PHONY: incident.forensics
incident.forensics: ## Collect post-incident forensics evidence
	@test -n "$(INCIDENT_ID)" || (echo "ERROR: INCIDENT_ID is required"; exit 1)
	bash "$(OPS_SCRIPTS_DIR)/forensics-collect.sh" "$(INCIDENT_ID)" $(FORENSICS_FLAGS)

.PHONY: incident.timeline
incident.timeline: ## Build derived timeline (INCIDENT_SOURCES="dir1 dir2"; CORRELATION_ID=...)
	@test -n "$(INCIDENT_SOURCES)" || (echo "ERROR: INCIDENT_SOURCES is required (space-separated evidence dirs)"; exit 1)
	@bash -euo pipefail -c '\
		if [[ -f "$(OPS_SCRIPTS_DIR)/correlation-timeline-builder.sh" ]]; then \
			bash "$(OPS_SCRIPTS_DIR)/correlation-timeline-builder.sh" "$(CORRELATION_ID)" $(INCIDENT_SOURCES); \
		else \
			echo "WARN: missing ops/scripts/correlation-timeline-builder.sh; cannot build timeline automatically." >&2; \
			echo "Hint: generate correlation artifacts manually using OPERATIONS_CROSS_INCIDENT_CORRELATION.md" >&2; \
		fi \
	'

###############################################################################
# Release readiness & promotion
###############################################################################

.PHONY: release.readiness
release.readiness: ## Create pre-release readiness packet
	@bash -euo pipefail -c '\
		rid="$(RELEASE_ID)"; \
		if [[ -z "$$rid" ]]; then rid="release-$$(date -u +%Y%m%d-%H%M%S)"; fi; \
		echo "RELEASE_ID=$$rid"; \
		if [[ -f "$(OPS_SCRIPTS_DIR)/pre-release-readiness.sh" ]]; then \
			bash "$(OPS_SCRIPTS_DIR)/pre-release-readiness.sh" "$$rid" "$(ENV)"; \
		else \
			echo "WARN: missing ops/scripts/pre-release-readiness.sh; cannot scaffold readiness packet." >&2; \
			echo "Hint: follow OPERATIONS_PRE_RELEASE_READINESS.md and create release-readiness/<release-id>/ manually." >&2; \
		fi \
	'

.PHONY: promote.release
promote.release: ## Promote a release after readiness & compliance
	@test -n "$(RELEASE_ID)" || (echo "RELEASE_ID is required"; exit 1)
	@echo "Release $(RELEASE_ID) ready for promotion to $(DST_ENV)"
	@echo "Apply manually after review."

###############################################################################
# Ops doctor
###############################################################################

.PHONY: ops.doctor
ops.doctor: ## Ops diagnostics (DOCTOR_FULL=1 for extended)
	@echo "ENV=$(ENV)"
	@packer version || true
	@terraform version || true
	@ansible --version || true
	@pre-commit --version || true
	@bash -euo pipefail -c '\
		echo ""; \
		echo "== Env (presence only; secrets not printed) =="; \
		for v in PM_API_URL PM_API_TOKEN_ID PM_API_TOKEN_SECRET TF_VAR_pm_api_url TF_VAR_pm_api_token_id TF_VAR_pm_api_token_secret COMPLIANCE_GPG_KEY COMPLIANCE_GPG_KEYS COMPLIANCE_TSA_URL COMPLIANCE_TSA_CA; do \
			if [[ -n "$${!v:-}" ]]; then echo "$$v=set"; else echo "$$v=missing"; fi; \
		done; \
		echo ""; \
		echo "== TLS guardrails (only enforced when Proxmox vars are set) =="; \
		bash "$(FABRIC_CI_DIR)/check-proxmox-ca-and-tls.sh" || true \
	'
	@if [ "$(DOCTOR_FULL)" = "1" ]; then \
		echo "Running extended checks (read-only)"; \
		bash "$(OPS_SCRIPTS_DIR)/ha-precheck.sh" || true; \
		bash "$(OPS_SCRIPTS_DIR)/drift-audit.sh" "$(ENV)" || true; \
	fi

###############################################################################
# Legacy / application build (C/C++)
# NOTE: Preserved for backward compatibility
###############################################################################

CXX ?= g++
CXXFLAGS ?= -Wall -Werror -Wextra -pedantic -std=c++17 -g -fsanitize=address
LDFLAGS ?= -fsanitize=address

SRC ?=
OBJ := $(SRC:.cc=.o)
EXEC ?= main

.PHONY: app.build app.clean clean

app.build: ## Build legacy C/C++ application
	@test -n "$(SRC)" || (echo "SRC is empty; nothing to build"; exit 1)
	$(CXX) $(CXXFLAGS) -c $(SRC)
	$(CXX) $(LDFLAGS) -o $(EXEC) $(OBJ)

app.clean: ## Clean legacy C/C++ build artifacts
	rm -f $(OBJ) $(EXEC)

clean: ## Backward-compatible clean target
	$(MAKE) app.clean || true

###############################################################################
# END
###############################################################################
