###############################################################################
# Samakia Fabric – Makefile
# Purpose: Deterministic GitOps / IaaS / Compliance / Incident lifecycle
###############################################################################

.DEFAULT_GOAL := help
SHELL := bash
.SHELLFLAGS := -euo pipefail -c

###############################################################################
# Global variables (override via env or CLI)
###############################################################################

# Environments
ENV ?= samakia-prod
SRC_ENV ?= samakia-dev
DST_ENV ?= samakia-prod

# Paths
PACKER_DIR := fabric-core/packer/lxc/ubuntu-24.04
PACKER_SCRIPTS_DIR := fabric-core/packer/lxc/scripts
PACKER_TEMPLATE := packer.pkr.hcl
TERRAFORM_ENV_DIR := fabric-core/terraform/envs/$(ENV)
ANSIBLE_DIR := fabric-core/ansible

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

# Compliance flags
COMPLIANCE_VERIFY_GLOB ?= compliance/$(ENV)/snapshot-*

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
image.build: ## Build golden LXC image via Packer
	@test -d "$(PACKER_DIR)" || (echo "ERROR: PACKER_DIR not found: $(PACKER_DIR)"; exit 1)
	@command -v packer >/dev/null 2>&1 || (echo "ERROR: packer not found in PATH"; exit 1)
	cd "$(PACKER_DIR)"
	packer init .
	packer validate .
	packer build "$(PACKER_TEMPLATE)"

.PHONY: image.upload
image.upload: ## Upload golden image to Proxmox via API (IMAGE=... or interactive)
	@test -d "$(PACKER_SCRIPTS_DIR)" || (echo "ERROR: PACKER_SCRIPTS_DIR not found: $(PACKER_SCRIPTS_DIR)"; exit 1)
	@test -x "$(PACKER_SCRIPTS_DIR)/upload-lxc-template-via-api.sh" || (echo "ERROR: upload script not executable: $(PACKER_SCRIPTS_DIR)/upload-lxc-template-via-api.sh"; exit 1)
	@command -v curl >/dev/null 2>&1 || (echo "ERROR: curl not found in PATH"; exit 1)
	@command -v python3 >/dev/null 2>&1 || (echo "ERROR: python3 not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		: "$${PM_API_URL:?ERROR: set PM_API_URL (Proxmox API URL)}"; \
		: "$${PM_API_TOKEN_ID:?ERROR: set PM_API_TOKEN_ID (must include !)}"; \
		: "$${PM_API_TOKEN_SECRET:?ERROR: set PM_API_TOKEN_SECRET}"; \
		image="$${IMAGE:-}"; \
		if [[ -z "$$image" ]]; then \
			if [[ ! -t 0 || ! -t 1 ]]; then \
				echo "ERROR: IMAGE is required in non-interactive mode (e.g. make image.upload IMAGE=...)" >&2; \
				exit 1; \
			fi; \
			mapfile -t candidates < <(ls -1 "$(PACKER_DIR)"/ubuntu-24.04-lxc-rootfs-v*.tar.gz 2>/dev/null || true); \
			if [[ "$${#candidates[@]}" -eq 0 ]]; then \
				mapfile -t candidates < <(ls -1 "$(PACKER_DIR)"/*.tar.gz 2>/dev/null || true); \
			fi; \
			if [[ "$${#candidates[@]}" -eq 0 ]]; then \
				echo "ERROR: no .tar.gz images found under $(PACKER_DIR)" >&2; \
				exit 1; \
			fi; \
			if command -v fzf >/dev/null 2>&1; then \
				image="$$(printf "%s\n" "$${candidates[@]}" | fzf --prompt="Select rootfs tar.gz to upload: " --height=15 --border)"; \
			else \
				echo "fzf not found; falling back to numbered selection (set IMAGE=... to avoid prompts)."; \
				PS3="Select rootfs tar.gz to upload: "; \
				select opt in "$${candidates[@]}"; do \
					image="$$opt"; \
					break; \
				done; \
			fi; \
			if [[ -z "$$image" ]]; then \
				echo "ERROR: no image selected" >&2; \
				exit 1; \
			fi; \
		fi; \
		if [[ ! -f "$$image" ]]; then \
			echo "ERROR: IMAGE not found: $$image" >&2; \
			exit 1; \
		fi; \
		bash "$(PACKER_SCRIPTS_DIR)/upload-lxc-template-via-api.sh" "$$image" \
	'


.PHONY: image.promote
image.promote: ## Promote image version (GitOps-only: prints the exact pin to apply in Terraform)
	@bash -euo pipefail -c '\
		if [[ ! -t 0 || ! -t 1 ]]; then \
			echo "NOTE: non-interactive shell; set IMAGE=... for explicit selection." >&2; \
		fi; \
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
				echo "fzf not found; falling back to numbered selection (set IMAGE=... to avoid prompts)."; \
				PS3="Select image to promote: "; \
				select opt in "$${candidates[@]}"; do \
					image="$$opt"; \
					break; \
				done; \
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
	cd "$(ANSIBLE_DIR)"
	FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
		ansible-inventory -i "$(ANSIBLE_INVENTORY)" --list

.PHONY: ansible.bootstrap
ansible.bootstrap: ## Phase-1 bootstrap (root-only)
	@test -d "$(ANSIBLE_DIR)" || (echo "ERROR: ANSIBLE_DIR not found: $(ANSIBLE_DIR)"; exit 1)
	@command -v ansible-playbook >/dev/null 2>&1 || (echo "ERROR: ansible-playbook not found in PATH"; exit 1)
	cd "$(ANSIBLE_DIR)"
	@test -f "$(ANSIBLE_BOOTSTRAP_KEYS_FILE)" || ( \
		echo "ERROR: missing bootstrap keys file: $(ANSIBLE_DIR)/$(ANSIBLE_BOOTSTRAP_KEYS_FILE)"; \
		echo "Create it (untracked) with: bootstrap_authorized_keys: [\"ssh-ed25519 ...\"]"; \
		exit 1 \
	)
	FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
		ansible-playbook -i "$(ANSIBLE_INVENTORY)" playbooks/bootstrap.yml -u root -e @"$(ANSIBLE_BOOTSTRAP_KEYS_FILE)" $(ANSIBLE_FLAGS)

.PHONY: ansible.harden
ansible.harden: ## Phase-2 hardening (runs as samakia)
	@test -d "$(ANSIBLE_DIR)" || (echo "ERROR: ANSIBLE_DIR not found: $(ANSIBLE_DIR)"; exit 1)
	@command -v ansible-playbook >/dev/null 2>&1 || (echo "ERROR: ansible-playbook not found in PATH"; exit 1)
	cd "$(ANSIBLE_DIR)"
	FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
		ansible-playbook -i "$(ANSIBLE_INVENTORY)" playbooks/harden.yml -u "$(ANSIBLE_USER)" $(ANSIBLE_FLAGS)

###############################################################################
# Drift / Compliance / Audit
###############################################################################

.PHONY: audit.drift
audit.drift: ## Read-only drift detection
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	@command -v ansible-playbook >/dev/null 2>&1 || (echo "ERROR: ansible-playbook not found in PATH"; exit 1)
	bash ops/scripts/drift-audit.sh "$(ENV)"

.PHONY: compliance.snapshot
compliance.snapshot: ## Create signed compliance snapshot
	bash ops/scripts/compliance-snapshot.sh "$(ENV)"

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
			if [[ "$${#candidates[@]}" -eq 0 ]]; then \
				echo "ERROR: no snapshots found matching: $(COMPLIANCE_VERIFY_GLOB)" >&2; \
				exit 1; \
			fi; \
			if command -v fzf >/dev/null 2>&1; then \
				dir="$$(printf "%s\n" "$${candidates[@]}" | fzf --prompt="Select snapshot to verify: " --height=15 --border)"; \
			else \
				echo "fzf not found; falling back to numbered selection (set SNAPSHOT_DIR=... to avoid prompts)."; \
				PS3="Select snapshot to verify: "; \
				select opt in "$${candidates[@]}"; do \
					dir="$$opt"; \
					break; \
				done; \
			fi; \
			if [[ -z "$$dir" ]]; then \
				echo "ERROR: no snapshot selected" >&2; \
				exit 1; \
			fi; \
		fi; \
		if [[ ! -d "$$dir" ]]; then \
			echo "ERROR: SNAPSHOT_DIR not found: $$dir" >&2; \
			exit 1; \
		fi; \
		bash ops/scripts/verify-compliance-snapshot.sh "$$dir" \
	'

###############################################################################
# Compliance packing & export
###############################################################################

.PHONY: compliance.pack
compliance.pack: ## Package evidence sources (PACK_SOURCES="dir1 dir2"; default: tar into audit/exports)
	@test -n "$(PACK_SOURCES)" || (echo "ERROR: PACK_SOURCES is required (space-separated list of evidence directories)"; exit 1)
	@mkdir -p "audit/exports/$(PACK_NAME)"
	@bash -euo pipefail -c '\
		out="audit/exports/$(PACK_NAME)"; \
		tarball="$$out/$(PACK_NAME).tar.gz"; \
		printf "%s\n" $(PACK_SOURCES) >"$$out/sources.txt"; \
		for d in $(PACK_SOURCES); do \
			if [[ ! -e "$$d" ]]; then echo "ERROR: source not found: $$d" >&2; exit 1; fi; \
		done; \
		if tar --help 2>/dev/null | grep -q -- "--sort"; then \
			tar --sort=name --mtime="@0" --owner=0 --group=0 --numeric-owner -czf "$$tarball" $(PACK_SOURCES); \
		else \
			tar -czf "$$tarball" $(PACK_SOURCES); \
		fi; \
		sha256sum "$$tarball" >"$$out/$(PACK_NAME).tar.gz.sha256"; \
		echo "OK: pack created: $$tarball"; \
		echo "OK: sha256: $$out/$(PACK_NAME).tar.gz.sha256" \
	'

.PHONY: audit.export
audit.export: ## Export audit artifacts for external review
	@test -n "$(AUDIT_SOURCES)" || (echo "ERROR: AUDIT_SOURCES is required (space-separated list of directories/files)"; exit 1)
	@mkdir -p "audit/exports/$(AUDIT_EXPORT_ID)"
	@bash -euo pipefail -c '\
		out="audit/exports/$(AUDIT_EXPORT_ID)"; \
		tarball="$$out/$(AUDIT_EXPORT_ID).tar.gz"; \
		printf "%s\n" $(AUDIT_SOURCES) >"$$out/sources.txt"; \
		for d in $(AUDIT_SOURCES); do \
			if [[ ! -e "$$d" ]]; then echo "ERROR: source not found: $$d" >&2; exit 1; fi; \
		done; \
		if tar --help 2>/dev/null | grep -q -- "--sort"; then \
			tar --sort=name --mtime="@0" --owner=0 --group=0 --numeric-owner -czf "$$tarball" $(AUDIT_SOURCES) CHANGELOG.md; \
		else \
			tar -czf "$$tarball" $(AUDIT_SOURCES) CHANGELOG.md; \
		fi; \
		sha256sum "$$tarball" >"$$out/$(AUDIT_EXPORT_ID).tar.gz.sha256"; \
		echo "OK: audit export created: $$tarball" \
	'

###############################################################################
# Legal hold / retention
###############################################################################

.PHONY: legal-hold
legal-hold: ## Manage legal-hold labels
	@bash -euo pipefail -c '\
		action="$(LEGAL_HOLD_ACTION)"; \
		case "$$action" in \
			list) bash ops/scripts/legal-hold-manage.sh list ;; \
			validate) : "$${EVIDENCE_DIR:?ERROR: set EVIDENCE_DIR}"; bash ops/scripts/legal-hold-manage.sh validate --path "$$EVIDENCE_DIR" ;; \
			require-dual-control) : "$${EVIDENCE_DIR:?ERROR: set EVIDENCE_DIR}"; \
				if [[ -n "$${GPG_KEYS:-}" ]]; then bash ops/scripts/legal-hold-manage.sh require-dual-control --path "$$EVIDENCE_DIR" --keys "$$GPG_KEYS"; \
				else bash ops/scripts/legal-hold-manage.sh require-dual-control --path "$$EVIDENCE_DIR"; fi ;; \
			declare) : "$${EVIDENCE_DIR:?ERROR: set EVIDENCE_DIR}"; : "$${HOLD_ID:?ERROR: set HOLD_ID}"; : "$${DECLARED_BY:?ERROR: set DECLARED_BY}"; : "$${HOLD_REASON:?ERROR: set HOLD_REASON}"; : "$${REVIEW_DATE:?ERROR: set REVIEW_DATE (YYYY-MM-DD)}"; \
				bash ops/scripts/legal-hold-manage.sh declare --path "$$EVIDENCE_DIR" --hold-id "$$HOLD_ID" --declared-by "$$DECLARED_BY" --reason "$$HOLD_REASON" --review-date "$$REVIEW_DATE" ;; \
			release) : "$${EVIDENCE_DIR:?ERROR: set EVIDENCE_DIR}"; : "$${RELEASED_BY:?ERROR: set RELEASED_BY}"; : "$${RELEASE_REASON:?ERROR: set RELEASE_REASON}"; \
				bash ops/scripts/legal-hold-manage.sh release --path "$$EVIDENCE_DIR" --released-by "$$RELEASED_BY" --reason "$$RELEASE_REASON" ;; \
			*) echo "ERROR: unknown LEGAL_HOLD_ACTION=$$action (use list|validate|declare|require-dual-control|release)" >&2; exit 2 ;; \
		esac \
	'

###############################################################################
# Incident response / forensics
###############################################################################

.PHONY: incident.forensics
incident.forensics: ## Collect post-incident forensics evidence
	@test -n "$(INCIDENT_ID)" || (echo "ERROR: INCIDENT_ID is required"; exit 1)
	bash ops/scripts/forensics-collect.sh "$(INCIDENT_ID)" $(FORENSICS_FLAGS)

.PHONY: incident.timeline
incident.timeline: ## Build derived timeline (INCIDENT_SOURCES="dir1 dir2"; CORRELATION_ID=...)
	@test -n "$(INCIDENT_SOURCES)" || (echo "ERROR: INCIDENT_SOURCES is required (space-separated evidence dirs)"; exit 1)
	bash ops/scripts/correlation-timeline-builder.sh "$(CORRELATION_ID)" $(INCIDENT_SOURCES)

###############################################################################
# Release readiness & promotion
###############################################################################

.PHONY: release.readiness
release.readiness: ## Create pre-release readiness packet
	@test -n "$(RELEASE_ID)" || (echo "ERROR: RELEASE_ID is required"; exit 1)
	bash ops/scripts/pre-release-readiness.sh "$(RELEASE_ID)" "$(ENV)"

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
	@bash fabric-ci/scripts/check-proxmox-ca-and-tls.sh || true
	@if [ "$(DOCTOR_FULL)" = "1" ]; then \
		echo "Running extended checks (read-only)"; \
		bash ops/scripts/ha-precheck.sh || true; \
		bash ops/scripts/drift-audit.sh "$(ENV)" || true; \
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
