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

# Canonical repo root for bootstrap-safe local-exec (must not rely on cwd)
FABRIC_REPO_ROOT ?= $(shell git -C "$(REPO_ROOT)" rev-parse --show-toplevel 2>/dev/null || echo "$(REPO_ROOT)")
export FABRIC_REPO_ROOT
export TF_VAR_fabric_repo_root ?= $(FABRIC_REPO_ROOT)
export RUNNER_MODE

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
PACKER_NEXT_VERSION_SCRIPT ?= $(OPS_SCRIPTS_DIR)/image-next-version.sh

# VM image build/validation (Phase 8 Part 1)
VM_PACKER_ROOT ?= $(REPO_ROOT)/images/packer
VM_PACKER_COMMON ?= $(VM_PACKER_ROOT)/common
VM_ANSIBLE_PLAYBOOK ?= $(REPO_ROOT)/images/ansible/playbooks/golden-base.yml
VM_VALIDATE_DIR ?= $(REPO_ROOT)/ops/images/vm/validate
VM_EVIDENCE_DIR ?= $(REPO_ROOT)/ops/images/vm/evidence
VM_REGISTER_DIR ?= $(REPO_ROOT)/ops/images/vm/register

TERRAFORM_ENV_DIR := $(REPO_ROOT)/fabric-core/terraform/envs/$(ENV)
ANSIBLE_DIR := $(REPO_ROOT)/fabric-core/ansible

OPS_SCRIPTS_DIR := $(REPO_ROOT)/ops/scripts
POLICY_DIR := $(REPO_ROOT)/ops/policy
FABRIC_CI_DIR := $(REPO_ROOT)/fabric-ci/scripts

# Runner host env file (canonical)
RUNNER_ENV_FILE ?= $(HOME)/.config/samakia-fabric/env.sh

# MinIO bootstrap workspace (runner-local; keeps backend.tf in Git while bootstrapping local state)
MINIO_BOOTSTRAP_DIR ?= $(HOME)/.cache/samakia-fabric/tf-bootstrap/samakia-minio

# Optional inputs
IMAGE ?=
VERSION ?=
QCOW2 ?=
TEMPLATE_STORAGE ?=
TEMPLATE_VM_ID ?=
TEMPLATE_NODE ?= $(PM_NODE)
RELEASE_ID ?=
SNAPSHOT_DIR ?=
EVIDENCE_DIR ?=
PACK_SOURCES ?=
AUDIT_SOURCES ?=
INCIDENT_SOURCES ?=
INCIDENT_ID ?= incident-$(shell date -u +%Y%m%d-%H%M%S)
CORRELATION_ID ?= corr-$(shell date -u +%Y%m%d-%H%M%S)
VIP_GROUP ?= minio
SERVICE ?= keepalived
TARGET ?= 192.168.11.111
CHECK_URL ?= https://192.168.11.122:3000/
PACK_NAME ?= compliance-pack-$(shell date -u +%Y%m%d-%H%M%S)
AUDIT_EXPORT_ID ?= audit-export-$(shell date -u +%Y%m%d-%H%M%S)
LEGAL_HOLD_ACTION ?= list
FORENSICS_FLAGS ?= --env $(ENV)
DOCTOR_FULL ?= 0
RUNNER_MODE ?= ci
PACKER_IMAGE_NAME ?= ubuntu-24.04-lxc-rootfs
APT_SNAPSHOT_URL ?= https://snapshot.ubuntu.com/ubuntu/20260102T000000Z
PACKER_TEMPLATE_ID ?= fabric-core/packer/lxc/ubuntu-24.04/packer.pkr.hcl

# Non-interactive / CI defaults
CI ?= 0
INTERACTIVE ?= 0
MIGRATE_STATE ?= 0

# Terraform flags
TF_INIT_FLAGS ?=
TF_PLAN_FLAGS ?=
TF_APPLY_FLAGS ?=
TF_LOCK_TIMEOUT ?= 60s

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
# Phase 1 – Runner host bootstrapping
###############################################################################

.PHONY: runner.env.install
runner.env.install: ## Install runner env file (~/.config/samakia-fabric/env.sh; chmod 600)
	bash "$(OPS_SCRIPTS_DIR)/runner-env-install.sh" --file "$(RUNNER_ENV_FILE)"

.PHONY: runner.env.check
runner.env.check: ## Validate runner env (presence-only; validates Proxmox CA and backend CA if required)
	bash "$(OPS_SCRIPTS_DIR)/runner-env-check.sh" --file "$(RUNNER_ENV_FILE)"

.PHONY: backend.configure
backend.configure: ## Configure local MinIO backend (env + credentials + CA + TLS bundle; no secrets printed)
	bash "$(OPS_SCRIPTS_DIR)/backend-configure.sh" --file "$(RUNNER_ENV_FILE)"

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
image.build: ## Build golden LXC image (VERSION=N optional; default: next)
	@bash -euo pipefail -c '\
		if [[ -n "$(IMAGE)" ]]; then \
			case "$(IMAGE)" in \
				ubuntu-24.04|debian-12) \
					$(MAKE) image.vm.build IMAGE="$(IMAGE)" VERSION="$(VERSION)"; \
					exit $$?; \
					;; \
				*) \
					echo "ERROR: unknown VM IMAGE=$(IMAGE) (expected ubuntu-24.04|debian-12)" >&2; \
					exit 2; \
					;; \
			esac; \
		fi \
	'
	@test -d "$(PACKER_IMAGE_DIR)" || (echo "ERROR: PACKER_IMAGE_DIR not found: $(PACKER_IMAGE_DIR)"; exit 1)
	@command -v packer >/dev/null 2>&1 || (echo "ERROR: packer not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		dir_abs="$$(cd "$(PACKER_IMAGE_DIR)" && pwd)"; \
		prefix="ubuntu-24.04-lxc-rootfs"; \
		version="$(VERSION)"; \
		if [[ -z "$$version" ]]; then \
			next="$$(bash "$(PACKER_NEXT_VERSION_SCRIPT)" --dir "$$dir_abs")"; \
		else \
			version="$${version#v}"; \
			if [[ ! "$$version" =~ ^[0-9]+$$ ]]; then echo "ERROR: VERSION must be numeric or vN (got: $(VERSION))" >&2; exit 2; fi; \
			next="$$version"; \
		fi; \
		fabric_version="v$${next}"; \
		artifact_basename="$${prefix}-v$${next}"; \
		git_sha="$$(git -C "$(REPO_ROOT)" rev-parse HEAD 2>/dev/null || echo unknown)"; \
		out="$$dir_abs/$${artifact_basename}.tar.gz"; \
		if [[ -e "$$out" ]]; then echo "ERROR: artifact already exists (refusing to overwrite): $$out" >&2; exit 1; fi; \
		echo "max+1 build: artifact=$${artifact_basename}.tar.gz"; \
		cd "$$dir_abs"; \
		packer init .; \
		packer validate .; \
		packer build \
			-var "fabric_version=$$fabric_version" \
			-var "artifact_basename=$$artifact_basename" \
			-var "image_name=$(PACKER_IMAGE_NAME)" \
			-var "image_version=$$fabric_version" \
			-var "build_time=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
			-var "git_sha=$$git_sha" \
			-var "packer_template_id=$(PACKER_TEMPLATE_ID)" \
			-var "apt_snapshot_url=$(APT_SNAPSHOT_URL)" \
			"$(PACKER_TEMPLATE)"; \
		if [[ ! -f "$$out" ]]; then echo "ERROR: build completed but artifact not found: $$out" >&2; exit 1; fi; \
		echo "$$out" \
	'

.PHONY: image.build-next
image.build-next: ## Build next image version v{max+1} (deterministic, no overwrite)
	@test -d "$(PACKER_IMAGE_DIR)" || (echo "ERROR: PACKER_IMAGE_DIR not found: $(PACKER_IMAGE_DIR)"; exit 1)
	@command -v packer >/dev/null 2>&1 || (echo "ERROR: packer not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		dir_abs="$$(cd "$(PACKER_IMAGE_DIR)" && pwd)"; \
		prefix="ubuntu-24.04-lxc-rootfs"; \
		# Robust max version discovery is delegated to a unit-tested resolver script. \
		next="$$(bash "$(PACKER_NEXT_VERSION_SCRIPT)" --dir "$$dir_abs")"; \
		max="$$((next-1))"; \
		fabric_version="v$${next}"; \
		artifact_basename="$${prefix}-v$${next}"; \
		git_sha="$$(git -C "$(REPO_ROOT)" rev-parse HEAD 2>/dev/null || echo unknown)"; \
		out="$$dir_abs/$${artifact_basename}.tar.gz"; \
		if [[ -e "$$out" ]]; then \
			echo "ERROR: next artifact already exists (refusing to overwrite): $$out" >&2; \
			exit 1; \
		fi; \
		echo "Discovered max version: v$${max}"; \
		echo "Selected next version:  v$${next}"; \
		echo "Output artifact path:  $$out"; \
		cd "$$dir_abs"; \
		packer init .; \
		packer validate .; \
		packer build \
			-var "fabric_version=$$fabric_version" \
			-var "artifact_basename=$$artifact_basename" \
			-var "image_name=$(PACKER_IMAGE_NAME)" \
			-var "image_version=$$fabric_version" \
			-var "build_time=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
			-var "git_sha=$$git_sha" \
			-var "packer_template_id=$(PACKER_TEMPLATE_ID)" \
			-var "apt_snapshot_url=$(APT_SNAPSHOT_URL)" \
			"$(PACKER_TEMPLATE)"; \
		if [[ ! -f "$$out" ]]; then \
			echo "ERROR: build completed but artifact not found: $$out" >&2; \
			echo "Directory listing:" >&2; \
			ls -lah "$$dir_abs" >&2 || true; \
			exit 1; \
		fi; \
			echo "$$out" \
	'

.PHONY: image.version.test
image.version.test: ## Unit test image version resolver (no packer, no Proxmox)
	bash "$(OPS_SCRIPTS_DIR)/test-image-next-version.sh"

.PHONY: image.vm.build
image.vm.build: ## Build VM golden image (IMAGE=ubuntu-24.04|debian-12 VERSION=v1; requires IMAGE_BUILD=1)
	@bash -euo pipefail -c '\
		if [[ "$(IMAGE_BUILD)" != "1" ]]; then \
			echo "ERROR: set IMAGE_BUILD=1 to run VM image builds" >&2; \
			exit 2; \
		fi; \
		if [[ -z "$(IMAGE)" || -z "$(VERSION)" ]]; then \
			echo "ERROR: IMAGE and VERSION are required (e.g., IMAGE=ubuntu-24.04 VERSION=v1)" >&2; \
			exit 2; \
		fi; \
		case "$(IMAGE)" in \
			ubuntu-24.04) vars_file="ubuntu24.pkrvars.hcl"; apt_snapshot_url="https://snapshot.ubuntu.com/ubuntu/20260102T000000Z"; apt_snapshot_security_url="" ;; \
			debian-12) vars_file="debian12.pkrvars.hcl"; apt_snapshot_url="https://snapshot.debian.org/archive/debian/20260102T000000Z"; apt_snapshot_security_url="https://snapshot.debian.org/archive/debian-security/20260102T000000Z" ;; \
			*) echo "ERROR: unsupported IMAGE=$(IMAGE)" >&2; exit 2 ;; \
		esac; \
		common_dir="$(VM_PACKER_COMMON)"; \
		vm_dir="$(VM_PACKER_ROOT)/$(IMAGE)/$(VERSION)"; \
		if [[ ! -d "$$common_dir" ]]; then echo "ERROR: missing VM packer common dir: $$common_dir" >&2; exit 1; fi; \
		if [[ ! -d "$$vm_dir" ]]; then echo "ERROR: missing VM packer dir: $$vm_dir" >&2; exit 1; fi; \
		command -v packer >/dev/null 2>&1 || (echo "ERROR: packer not found in PATH" >&2; exit 1); \
		out_dir="$(REPO_ROOT)/artifacts/images/vm/$(IMAGE)/$(VERSION)"; \
		if [[ -d "$$out_dir" && -n "$$(ls -A "$$out_dir" 2>/dev/null)" ]]; then \
			echo "ERROR: output dir not empty (refusing to overwrite): $$out_dir" >&2; \
			exit 1; \
		fi; \
		tmp_dir="$(REPO_ROOT)/artifacts/packer-vm/$(IMAGE)-$(VERSION)"; \
		rm -rf "$$tmp_dir"; \
		mkdir -p "$$tmp_dir"; \
		cp -a "$$common_dir/"*.pkr.hcl "$$tmp_dir/"; \
		cp -a "$$common_dir/scripts" "$$tmp_dir/"; \
		cp -a "$$vm_dir/"*.pkr.hcl "$$tmp_dir/"; \
		cp -a "$$vm_dir/$$vars_file" "$$tmp_dir/"; \
		git_sha="$$(git -C "$(REPO_ROOT)" rev-parse HEAD 2>/dev/null || echo unknown)"; \
		packer_template_id="images/packer/$(IMAGE)/$(VERSION)/image.pkr.hcl"; \
		packer init "$$tmp_dir"; \
		packer build \
			-var-file "$$tmp_dir/$$vars_file" \
			-var "ansible_playbook_path=$(VM_ANSIBLE_PLAYBOOK)" \
			-var "output_dir=$$out_dir" \
			-var "vm_name=$(IMAGE)-$(VERSION)" \
			-var "image_id=$(IMAGE)" \
			-var "image_version=$(VERSION)" \
			-var "build_time=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
			-var "git_sha=$$git_sha" \
			-var "packer_template_id=$$packer_template_id" \
			-var "apt_snapshot_url=$$apt_snapshot_url" \
			-var "apt_snapshot_security_url=$$apt_snapshot_security_url" \
			"$$tmp_dir"; \
		echo "$$out_dir" \
	'

.PHONY: images.vm.validate.contracts
images.vm.validate.contracts: ## Validate VM image contracts (schema + semantics)
	@bash "$(VM_VALIDATE_DIR)/validate-image-schema.sh"
	@bash "$(VM_VALIDATE_DIR)/validate-image-semantics.sh"

.PHONY: image.tools.check
image.tools.check: ## Check local VM image tooling prerequisites
	@bash "$(VM_VALIDATE_DIR)/tools-check.sh"

.PHONY: image.validate
image.validate: ## Validate a local VM qcow2 artifact (QCOW2=... IMAGE=... VERSION=...)
	@test -n "$(QCOW2)" || (echo "ERROR: QCOW2 is required"; exit 2)
	@bash "$(VM_VALIDATE_DIR)/validate-image.sh" --qcow2 "$(QCOW2)"

.PHONY: image.evidence.build
image.evidence.build: ## Generate VM image build evidence (QCOW2=... IMAGE=... VERSION=...)
	@test -n "$(QCOW2)" || (echo "ERROR: QCOW2 is required"; exit 2)
	@test -n "$(IMAGE)" || (echo "ERROR: IMAGE is required"; exit 2)
	@test -n "$(VERSION)" || (echo "ERROR: VERSION is required"; exit 2)
	@bash "$(VM_EVIDENCE_DIR)/image-build-evidence.sh" --qcow2 "$(QCOW2)" --image "$(IMAGE)" --version "$(VERSION)"

.PHONY: image.evidence.validate
image.evidence.validate: ## Generate VM image validation evidence (QCOW2=... IMAGE=... VERSION=...)
	@test -n "$(QCOW2)" || (echo "ERROR: QCOW2 is required"; exit 2)
	@test -n "$(IMAGE)" || (echo "ERROR: IMAGE is required"; exit 2)
	@test -n "$(VERSION)" || (echo "ERROR: VERSION is required"; exit 2)
	@bash "$(VM_EVIDENCE_DIR)/image-validate-evidence.sh" --qcow2 "$(QCOW2)" --image "$(IMAGE)" --version "$(VERSION)"

.PHONY: images.vm.register.policy.check
images.vm.register.policy.check: ## Validate VM template registration policy
	@bash "$(VM_REGISTER_DIR)/validate-register-policy.sh"

.PHONY: image.template.register
image.template.register: ## Register VM template in Proxmox (guarded; requires IMAGE_REGISTER=1)
	@test -n "$(IMAGE)" || (echo "ERROR: IMAGE is required"; exit 2)
	@test -n "$(VERSION)" || (echo "ERROR: VERSION is required"; exit 2)
	@test -n "$(QCOW2)" || (echo "ERROR: QCOW2 is required"; exit 2)
	@test -n "$(TEMPLATE_STORAGE)" || (echo "ERROR: TEMPLATE_STORAGE is required"; exit 2)
	@test -n "$(TEMPLATE_VM_ID)" || (echo "ERROR: TEMPLATE_VM_ID is required"; exit 2)
	@test -n "$(TEMPLATE_NODE)" || (echo "ERROR: TEMPLATE_NODE is required"; exit 2)
	@bash "$(VM_REGISTER_DIR)/register-template.sh" \
		--contract "$(REPO_ROOT)/contracts/images/vm/$(IMAGE)/$(VERSION)/image.yml" \
		--qcow2 "$(QCOW2)" \
		--env "$(ENV)" \
		--storage "$(TEMPLATE_STORAGE)" \
		--vmid "$(TEMPLATE_VM_ID)" \
		--node "$(TEMPLATE_NODE)"

.PHONY: image.template.verify
image.template.verify: ## Verify VM template in Proxmox (read-only)
	@test -n "$(IMAGE)" || (echo "ERROR: IMAGE is required"; exit 2)
	@test -n "$(VERSION)" || (echo "ERROR: VERSION is required"; exit 2)
	@test -n "$(TEMPLATE_STORAGE)" || (echo "ERROR: TEMPLATE_STORAGE is required"; exit 2)
	@test -n "$(TEMPLATE_VM_ID)" || (echo "ERROR: TEMPLATE_VM_ID is required"; exit 2)
	@test -n "$(TEMPLATE_NODE)" || (echo "ERROR: TEMPLATE_NODE is required"; exit 2)
	@bash "$(VM_REGISTER_DIR)/verify-template.sh" \
		--contract "$(REPO_ROOT)/contracts/images/vm/$(IMAGE)/$(VERSION)/image.yml" \
		--env "$(ENV)" \
		--storage "$(TEMPLATE_STORAGE)" \
		--vmid "$(TEMPLATE_VM_ID)" \
		--node "$(TEMPLATE_NODE)"

.PHONY: phase8.part1.accept
phase8.part1.accept: ## Phase 8 Part 1 acceptance (validate-only; no builds)
	@bash "$(OPS_SCRIPTS_DIR)/phase8-part1-accept.sh"

.PHONY: image.local.full
image.local.full: ## Local VM build+validate+evidence (requires IMAGE_BUILD=1 I_UNDERSTAND_BUILDS_TAKE_TIME=1)
	@bash "$(REPO_ROOT)/ops/images/vm/local-run.sh" full --image "$(IMAGE)" --version "$(VERSION)"

.PHONY: image.local.validate
image.local.validate: ## Local VM qcow2 validation (QCOW2=... IMAGE=... VERSION=...)
	@bash "$(REPO_ROOT)/ops/images/vm/local-run.sh" validate --image "$(IMAGE)" --version "$(VERSION)" --qcow2 "$(QCOW2)"

.PHONY: image.local.evidence
image.local.evidence: ## Local VM validation evidence (QCOW2=... IMAGE=... VERSION=...)
	@bash "$(REPO_ROOT)/ops/images/vm/local-run.sh" evidence --image "$(IMAGE)" --version "$(VERSION)" --qcow2 "$(QCOW2)"

.PHONY: image.toolchain.build
image.toolchain.build: ## Build VM image using toolchain container (guarded)
	@bash "$(REPO_ROOT)/ops/images/vm/toolchain-run.sh" build --image "$(IMAGE)" --version "$(VERSION)"

.PHONY: image.toolchain.validate
image.toolchain.validate: ## Validate qcow2 using toolchain container
	@bash "$(REPO_ROOT)/ops/images/vm/toolchain-run.sh" validate --image "$(IMAGE)" --version "$(VERSION)" --qcow2 "$(QCOW2)"

.PHONY: image.toolchain.full
image.toolchain.full: ## Build+validate using toolchain container (guarded)
	@bash "$(REPO_ROOT)/ops/images/vm/toolchain-run.sh" full --image "$(IMAGE)" --version "$(VERSION)"

.PHONY: phase8.part1.1.accept
phase8.part1.1.accept: ## Phase 8 Part 1.1 acceptance (local runbook + wrappers)
	@bash "$(OPS_SCRIPTS_DIR)/phase8-part1-1-accept.sh"

.PHONY: phase8.part1.2.accept
phase8.part1.2.accept: ## Phase 8 Part 1.2 acceptance (toolchain container)
	@bash "$(OPS_SCRIPTS_DIR)/phase8-part1-2-accept.sh"

.PHONY: phase8.part2.accept
phase8.part2.accept: ## Phase 8 Part 2 acceptance (template registration; read-only)
	@bash "$(OPS_SCRIPTS_DIR)/phase8-part2-accept.sh"


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
		if [[ "$(RUNNER_MODE)" = "ci" || "$(INTERACTIVE)" != "1" || "$(CI)" = "1" || ! -t 0 || ! -t 1 ]]; then \
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
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
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
			if [[ "$(RUNNER_MODE)" = "ci" ]]; then \
				echo "ERROR: RUNNER_MODE=ci forbids interactive selection. Set IMAGE=... explicitly." >&2; \
				exit 2; \
			fi; \
			if [[ "$(INTERACTIVE)" != "1" || "$(CI)" = "1" || ! -t 0 || ! -t 1 ]]; then \
				echo "ERROR: IMAGE is required unless INTERACTIVE=1 (e.g. make image.upload IMAGE=...)" >&2; \
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
			if [[ "$(INTERACTIVE)" = "1" && "$(CI)" != "1" && -t 0 && -t 1 ]]; then \
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
		if [[ -z "$$image" && "$(RUNNER_MODE)" = "ci" ]]; then \
			echo "ERROR: RUNNER_MODE=ci forbids interactive selection. Set IMAGE=... explicitly." >&2; \
			exit 2; \
		fi; \
		if [[ -z "$$image" && "$(INTERACTIVE)" = "1" && "$(CI)" != "1" && -t 0 && -t 1 ]]; then \
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
			echo "ERROR: set IMAGE=... (or run with INTERACTIVE=1) to compute a promotion pin" >&2; \
			echo "Example: make image.promote IMAGE=$(PACKER_DIR)/ubuntu-24.04-lxc-rootfs-v3.tar.gz" >&2; \
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

.PHONY: tf.backend.init
tf.backend.init: ## Terraform backend init (remote S3/MinIO state; strict TLS; no prompts)
	@test "$(ENV)" != "samakia-minio" || (echo "ERROR: tf.backend.init is forbidden for ENV=samakia-minio (backend bootstrap invariant). Use: make minio.tf.apply ENV=samakia-minio (local state) then: make minio.state.migrate ENV=samakia-minio"; exit 2)
	@test -d "$(TERRAFORM_ENV_DIR)" || (echo "ERROR: Terraform env dir not found: $(TERRAFORM_ENV_DIR)"; exit 1)
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
			env_file="$(RUNNER_ENV_FILE)"; \
			if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) runner.env.check; \
		if [[ "$(MIGRATE_STATE)" = "1" ]]; then \
			bash "$(OPS_SCRIPTS_DIR)/tf-backend-init.sh" "$(ENV)" --migrate; \
		else \
			bash "$(OPS_SCRIPTS_DIR)/tf-backend-init.sh" "$(ENV)"; \
		fi \
	'

.PHONY: tf.init
tf.init: ## Terraform init for ENV
	@test "$(ENV)" != "samakia-minio" || (echo "ERROR: tf.init is forbidden for ENV=samakia-minio (backend bootstrap invariant). Use: make minio.tf.plan/minio.tf.apply ENV=samakia-minio"; exit 2)
	@test -d "$(TERRAFORM_ENV_DIR)" || (echo "ERROR: Terraform env dir not found: $(TERRAFORM_ENV_DIR)"; exit 1)
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
			env_file="$(RUNNER_ENV_FILE)"; \
			if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) tf.backend.init; \
		terraform -chdir="$(TERRAFORM_ENV_DIR)" init -input=false $(TF_INIT_FLAGS) >/dev/null; \
	'

.PHONY: tf.plan
tf.plan: ## Terraform plan for ENV
	@test "$(ENV)" != "samakia-minio" || (echo "ERROR: tf.plan is forbidden for ENV=samakia-minio (backend bootstrap invariant). Use: make minio.tf.plan ENV=samakia-minio"; exit 2)
	@test -d "$(TERRAFORM_ENV_DIR)" || (echo "ERROR: Terraform env dir not found: $(TERRAFORM_ENV_DIR)"; exit 1)
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
			env_file="$(RUNNER_ENV_FILE)"; \
			if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) tf.backend.init; \
		$(MAKE) ha.enforce.check ENV="$(ENV)"; \
		terraform -chdir="$(TERRAFORM_ENV_DIR)" validate; \
		terraform -chdir="$(TERRAFORM_ENV_DIR)" plan -input=false -lock-timeout="$(TF_LOCK_TIMEOUT)" $(TF_PLAN_FLAGS); \
	'

.PHONY: tf.apply
tf.apply: ## Terraform apply for ENV
	@test "$(ENV)" != "samakia-minio" || (echo "ERROR: tf.apply is forbidden for ENV=samakia-minio (backend bootstrap invariant). Use: make minio.tf.apply ENV=samakia-minio"; exit 2)
	@test -d "$(TERRAFORM_ENV_DIR)" || (echo "ERROR: Terraform env dir not found: $(TERRAFORM_ENV_DIR)"; exit 1)
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
				env_file="$(RUNNER_ENV_FILE)"; \
				if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
			$(MAKE) minio.backend.smoke ENV=samakia-minio; \
			$(MAKE) tf.backend.init; \
			$(MAKE) ha.enforce.check ENV="$(ENV)"; \
			auto_approve=""; \
			if [[ "$(CI)" = "1" ]]; then auto_approve="-auto-approve"; fi; \
			terraform -chdir="$(TERRAFORM_ENV_DIR)" validate; \
			terraform -chdir="$(TERRAFORM_ENV_DIR)" apply -input=false -lock-timeout="$(TF_LOCK_TIMEOUT)" $$auto_approve $(TF_APPLY_FLAGS); \
			terraform -chdir="$(TERRAFORM_ENV_DIR)" output -json > "$(TERRAFORM_ENV_DIR)/terraform-output.json"; \
		'

###############################################################################
# Ansible lifecycle
###############################################################################

.PHONY: ansible.inventory
ansible.inventory: ## Show resolved Ansible inventory
	@test -d "$(ANSIBLE_DIR)" || (echo "ERROR: ANSIBLE_DIR not found: $(ANSIBLE_DIR)"; exit 1)
	@command -v ansible-inventory >/dev/null 2>&1 || (echo "ERROR: ansible-inventory not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		if [[ "$(ENV)" = "samakia-minio" ]]; then \
			candidate="$(MINIO_BOOTSTRAP_DIR)/terraform-output.json"; \
			if [[ -f "$$candidate" ]]; then export TF_OUTPUT_PATH="$$candidate"; fi; \
		fi; \
		FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
			ansible-inventory -i "$(ANSIBLE_INVENTORY_PATH)" --list; \
	'

.PHONY: inventory.check
inventory.check: ## Validate inventory parse + DHCP/MAC/IP sanity (no DNS)
	@test -d "$(ANSIBLE_DIR)" || (echo "ERROR: ANSIBLE_DIR not found: $(ANSIBLE_DIR)"; exit 1)
	@command -v ansible-inventory >/dev/null 2>&1 || (echo "ERROR: ansible-inventory not found in PATH"; exit 1)
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) runner.env.check; \
		echo "Checking ansible-inventory parse..."; \
		if [[ "$(ENV)" = "samakia-minio" ]]; then \
			candidate="$(MINIO_BOOTSTRAP_DIR)/terraform-output.json"; \
			if [[ -f "$$candidate" ]]; then export TF_OUTPUT_PATH="$$candidate"; fi; \
		fi; \
		FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
			ansible-inventory -i "$(ANSIBLE_INVENTORY_PATH)" --list >/dev/null; \
		echo "Checking inventory sanity (DHCP/MAC/IP)..."; \
		bash "$(OPS_SCRIPTS_DIR)/inventory-sanity-check.sh" "$(ENV)"; \
	'

.PHONY: ansible.bootstrap
ansible.bootstrap: ## Phase-1 bootstrap (root-only)
	@test -d "$(ANSIBLE_DIR)" || (echo "ERROR: ANSIBLE_DIR not found: $(ANSIBLE_DIR)"; exit 1)
	@command -v ansible-playbook >/dev/null 2>&1 || (echo "ERROR: ansible-playbook not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		keys_arg=(); \
		if [[ -f "$(ANSIBLE_BOOTSTRAP_KEYS_PATH)" ]]; then keys_arg+=( -e @"$(ANSIBLE_BOOTSTRAP_KEYS_PATH)" ); fi; \
		if [[ "$(ENV)" = "samakia-minio" ]]; then \
			candidate="$(MINIO_BOOTSTRAP_DIR)/terraform-output.json"; \
			if [[ -f "$$candidate" ]]; then export TF_OUTPUT_PATH="$$candidate"; fi; \
		fi; \
		FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
			ansible-playbook -i "$(ANSIBLE_INVENTORY_PATH)" "$(ANSIBLE_DIR)/playbooks/bootstrap.yml" -u root "$${keys_arg[@]}" $(ANSIBLE_FLAGS); \
	'

.PHONY: ansible.harden
ansible.harden: ## Phase-2 hardening (runs as samakia)
	@test -d "$(ANSIBLE_DIR)" || (echo "ERROR: ANSIBLE_DIR not found: $(ANSIBLE_DIR)"; exit 1)
	@command -v ansible-playbook >/dev/null 2>&1 || (echo "ERROR: ansible-playbook not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		if [[ "$(ENV)" = "samakia-minio" ]]; then \
			candidate="$(MINIO_BOOTSTRAP_DIR)/terraform-output.json"; \
			if [[ -f "$$candidate" ]]; then export TF_OUTPUT_PATH="$$candidate"; fi; \
		fi; \
		FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
			ansible-playbook -i "$(ANSIBLE_INVENTORY_PATH)" "$(ANSIBLE_DIR)/playbooks/harden.yml" -u "$(ANSIBLE_USER)" $(ANSIBLE_FLAGS); \
	'

###############################################################################
# Drift / Compliance / Audit
###############################################################################

.PHONY: audit.drift
audit.drift: ## Read-only drift detection
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	@command -v ansible-playbook >/dev/null 2>&1 || (echo "ERROR: ansible-playbook not found in PATH"; exit 1)
	bash "$(OPS_SCRIPTS_DIR)/drift-audit.sh" "$(ENV)"

.PHONY: drift.detect
drift.detect: ## Tenant drift detection (read-only; TENANT required)
	@test -n "$(TENANT)" || (echo "ERROR: TENANT is required (use TENANT=all for all tenants)"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" TENANT="$(TENANT)" \
		DRIFT_OFFLINE="$(DRIFT_OFFLINE)" DRIFT_FAIL_ON="$(DRIFT_FAIL_ON)" \
		DRIFT_NON_BLOCKING="$(DRIFT_NON_BLOCKING)" DRIFT_REQUIRE_SIGN="$(DRIFT_REQUIRE_SIGN)" \
		DRIFT_EVIDENCE_ROOT="$(DRIFT_EVIDENCE_ROOT)" DRIFT_SUMMARY_ROOT="$(DRIFT_SUMMARY_ROOT)" \
		bash "$(REPO_ROOT)/ops/drift/detect.sh"

.PHONY: drift.classify
drift.classify: ## Classify drift (latest evidence; TENANT required)
	@test -n "$(TENANT)" || (echo "ERROR: TENANT is required"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" TENANT="$(TENANT)" \
		bash "$(REPO_ROOT)/ops/drift/classify.sh" --tenant "$(TENANT)"

.PHONY: drift.summary
drift.summary: ## Emit tenant drift summary (TENANT required)
	@test -n "$(TENANT)" || (echo "ERROR: TENANT is required"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" TENANT="$(TENANT)" DRIFT_SUMMARY_ROOT="$(DRIFT_SUMMARY_ROOT)" \
		bash "$(REPO_ROOT)/ops/drift/summary.sh"

###############################################################################
# Runtime operations (Phase 14)
###############################################################################

.PHONY: runtime.evaluate
runtime.evaluate: ## Evaluate runtime signals (TENANT required)
	@test -n "$(TENANT)" || (echo "ERROR: TENANT is required (use TENANT=all for all tenants)"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" \
		RUNTIME_EVIDENCE_ROOT="$(RUNTIME_EVIDENCE_ROOT)" RUNTIME_STATUS_ROOT="$(RUNTIME_STATUS_ROOT)" \
		DRIFT_EVIDENCE_ROOT="$(DRIFT_EVIDENCE_ROOT)" VERIFY_EVIDENCE_ROOT="$(VERIFY_EVIDENCE_ROOT)" \
		TENANT_EVIDENCE_ROOT="$(TENANT_EVIDENCE_ROOT)" \
		METRICS_SOURCE_DIR="$(METRICS_SOURCE_DIR)" METRICS_SOURCE="$(METRICS_SOURCE)" \
		bash "$(REPO_ROOT)/ops/runtime/evaluate.sh"

.PHONY: runtime.status
runtime.status: ## Emit runtime status summaries (TENANT required)
	@test -n "$(TENANT)" || (echo "ERROR: TENANT is required (use TENANT=all for all tenants)"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" \
		RUNTIME_EVIDENCE_ROOT="$(RUNTIME_EVIDENCE_ROOT)" RUNTIME_STATUS_ROOT="$(RUNTIME_STATUS_ROOT)" \
		bash "$(REPO_ROOT)/ops/runtime/status.sh"

.PHONY: slo.ingest.offline
slo.ingest.offline: ## Ingest SLO metrics offline (TENANT required)
	@test -n "$(TENANT)" || (echo "ERROR: TENANT is required (use TENANT=all for all SLO contracts)"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" \
		SLO_LIVE=0 SLO_METRICS_ROOT="$(SLO_METRICS_ROOT)" FIXTURES_ROOT="$(FIXTURES_ROOT)" \
		OBSERVATION_PATH="$(OBSERVATION_PATH)" \
		bash "$(REPO_ROOT)/ops/slo/ingest.sh"

.PHONY: slo.ingest.live
slo.ingest.live: ## Ingest SLO metrics live (guarded; TENANT required)
	@test -n "$(TENANT)" || (echo "ERROR: TENANT is required (use TENANT=all for all SLO contracts)"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" \
		SLO_LIVE=1 PROM_URL="$(PROM_URL)" PROM_QUERY_FILE="$(PROM_QUERY_FILE)" \
		SLO_METRICS_ROOT="$(SLO_METRICS_ROOT)" FIXTURES_ROOT="$(FIXTURES_ROOT)" \
		OBSERVATION_PATH="$(OBSERVATION_PATH)" \
		bash "$(REPO_ROOT)/ops/slo/ingest.sh"

.PHONY: slo.evaluate
slo.evaluate: ## Evaluate SLOs and emit evidence (TENANT required)
	@test -n "$(TENANT)" || (echo "ERROR: TENANT is required (use TENANT=all for all SLO contracts)"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" \
		SLO_EVIDENCE_ROOT="$(SLO_EVIDENCE_ROOT)" SLO_STATUS_ROOT="$(SLO_STATUS_ROOT)" \
		SLO_METRICS_ROOT="$(SLO_METRICS_ROOT)" OBSERVATION_PATH="$(OBSERVATION_PATH)" \
		bash "$(REPO_ROOT)/ops/slo/evaluate.sh"

.PHONY: slo.alerts.generate
slo.alerts.generate: ## Generate SLO alert readiness rules (TENANT required)
	@test -n "$(TENANT)" || (echo "ERROR: TENANT is required (use TENANT=all for all SLO contracts)"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" \
		SLO_ALERTS_ROOT="$(SLO_ALERTS_ROOT)" \
		bash "$(REPO_ROOT)/ops/slo/alerting/rules-generate.sh"
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" SLO_ALERTS_ROOT="$(SLO_ALERTS_ROOT)" \
		bash "$(REPO_ROOT)/ops/slo/alerting/rules-validate.sh"

.PHONY: alerts.validate
alerts.validate: ## Validate alert routing + formatting
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" \
		bash "$(REPO_ROOT)/ops/alerts/validate.sh"

.PHONY: alerts.deliver
alerts.deliver: ## Deliver alerts (guarded; TENANT required)
	@test -n "$(TENANT)" || (echo "ERROR: TENANT is required (use TENANT=all for all tenants)"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" \
		ALERTS_ENABLE="$(ALERTS_ENABLE)" ALERT_SINK="$(ALERT_SINK)" ALERTS_STAMP="$(ALERTS_STAMP)" \
		ALERTS_EVIDENCE_ROOT="$(ALERTS_EVIDENCE_ROOT)" RUNTIME_EVIDENCE_ROOT="$(RUNTIME_EVIDENCE_ROOT)" \
		SLO_EVIDENCE_ROOT="$(SLO_EVIDENCE_ROOT)" SLO_ALERTS_ROOT="$(SLO_ALERTS_ROOT)" \
		ALERTS_ROUTING_PATH="$(ALERTS_ROUTING_PATH)" \
		bash "$(REPO_ROOT)/ops/alerts/deliver.sh"

.PHONY: incidents.open
incidents.open: ## Open incident record (INCIDENT_ID required)
	@test -n "$(INCIDENT_ID)" || (echo "ERROR: INCIDENT_ID is required"; exit 1)
	@test -n "$(TENANT)" || (echo "ERROR: TENANT is required"; exit 1)
	@test -n "$(WORKLOAD)" || (echo "ERROR: WORKLOAD is required"; exit 1)
	@test -n "$(SIGNAL_TYPE)" || (echo "ERROR: SIGNAL_TYPE is required"; exit 1)
	@test -n "$(SEVERITY)" || (echo "ERROR: SEVERITY is required"; exit 1)
	@test -n "$(OWNER)" || (echo "ERROR: OWNER is required"; exit 1)
	@test -n "$(EVIDENCE_REFS)" || (echo "ERROR: EVIDENCE_REFS is required"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" INCIDENT_ID="$(INCIDENT_ID)" TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" \
		SIGNAL_TYPE="$(SIGNAL_TYPE)" SEVERITY="$(SEVERITY)" OWNER="$(OWNER)" \
		EVIDENCE_REFS="$(EVIDENCE_REFS)" OPENED_AT="$(OPENED_AT)" STATUS="$(STATUS)" \
		RESOLUTION_SUMMARY="$(RESOLUTION_SUMMARY)" INCIDENT_EVIDENCE_ROOT="$(INCIDENT_EVIDENCE_ROOT)" \
		bash "$(REPO_ROOT)/ops/incidents/open.sh"

.PHONY: incidents.update
incidents.update: ## Update incident record (INCIDENT_ID required)
	@test -n "$(INCIDENT_ID)" || (echo "ERROR: INCIDENT_ID is required"; exit 1)
	@test -n "$(UPDATE_SUMMARY)" || (echo "ERROR: UPDATE_SUMMARY is required"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" INCIDENT_ID="$(INCIDENT_ID)" UPDATE_SUMMARY="$(UPDATE_SUMMARY)" \
		UPDATED_AT="$(UPDATED_AT)" STATUS="$(STATUS)" UPDATE_NOTES="$(UPDATE_NOTES)" \
		EVIDENCE_REFS="$(EVIDENCE_REFS)" INCIDENT_EVIDENCE_ROOT="$(INCIDENT_EVIDENCE_ROOT)" \
		bash "$(REPO_ROOT)/ops/incidents/update.sh"

.PHONY: incidents.close
incidents.close: ## Close incident record (INCIDENT_ID required)
	@test -n "$(INCIDENT_ID)" || (echo "ERROR: INCIDENT_ID is required"; exit 1)
	@test -n "$(RESOLUTION_SUMMARY)" || (echo "ERROR: RESOLUTION_SUMMARY is required"; exit 1)
	@FABRIC_REPO_ROOT="$(REPO_ROOT)" INCIDENT_ID="$(INCIDENT_ID)" RESOLUTION_SUMMARY="$(RESOLUTION_SUMMARY)" \
		CLOSED_AT="$(CLOSED_AT)" STATUS="$(STATUS)" EVIDENCE_REFS="$(EVIDENCE_REFS)" \
		INCIDENT_EVIDENCE_ROOT="$(INCIDENT_EVIDENCE_ROOT)" \
		bash "$(REPO_ROOT)/ops/incidents/close.sh"

.PHONY: phase14.part1.entry.check
phase14.part1.entry.check: ## Phase 14 Part 1 entry checklist
	@bash "$(OPS_SCRIPTS_DIR)/phase14-part1-entry-check.sh"

.PHONY: phase14.part1.accept
phase14.part1.accept: ## Phase 14 Part 1 acceptance
	@bash "$(OPS_SCRIPTS_DIR)/phase14-part1-accept.sh"

.PHONY: phase14.part2.entry.check
phase14.part2.entry.check: ## Phase 14 Part 2 entry checklist
	@bash "$(OPS_SCRIPTS_DIR)/phase14-part2-entry-check.sh"

.PHONY: phase14.part2.accept
phase14.part2.accept: ## Phase 14 Part 2 acceptance
	@bash "$(OPS_SCRIPTS_DIR)/phase14-part2-accept.sh"

.PHONY: phase14.part3.entry.check
phase14.part3.entry.check: ## Phase 14 Part 3 entry checklist
	@bash "$(OPS_SCRIPTS_DIR)/phase14-part3-entry-check.sh"

.PHONY: phase14.part3.accept
phase14.part3.accept: ## Phase 14 Part 3 acceptance
	@bash "$(OPS_SCRIPTS_DIR)/phase14-part3-accept.sh"

.PHONY: compliance.snapshot
compliance.snapshot: ## Create signed compliance snapshot
	bash "$(OPS_SCRIPTS_DIR)/compliance-snapshot.sh" "$(ENV)"

.PHONY: compliance.verify
compliance.verify: ## Verify compliance snapshot offline (SNAPSHOT_DIR=... or interactive)
	@bash -euo pipefail -c '\
		dir="$${SNAPSHOT_DIR:-}"; \
		if [[ -z "$$dir" ]]; then \
			if [[ "$(RUNNER_MODE)" = "ci" ]]; then \
				echo "ERROR: RUNNER_MODE=ci forbids interactive selection. Set SNAPSHOT_DIR=... explicitly." >&2; \
				exit 2; \
			fi; \
			if [[ "$(INTERACTIVE)" != "1" || "$(CI)" = "1" || ! -t 0 || ! -t 1 ]]; then \
				echo "ERROR: SNAPSHOT_DIR is required unless INTERACTIVE=1 (e.g. make compliance.verify SNAPSHOT_DIR=...)" >&2; \
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
# Phase 1 – Operational Hardening targets
###############################################################################

.PHONY: env.parity.check
env.parity.check: ## Enforce env parity (dev/staging/prod Terraform structure)
	bash "$(OPS_SCRIPTS_DIR)/env-parity-check.sh"

.PHONY: ssh.trust.rotate
ssh.trust.rotate: ## Rotate known_hosts entry for HOST=... (no enroll by default)
	@test -n "$(HOST)" || (echo "ERROR: HOST is required (e.g. make ssh.trust.rotate HOST=192.0.2.10)"; exit 1)
	bash "$(OPS_SCRIPTS_DIR)/ssh-trust-rotate.sh" --host "$(HOST)"

.PHONY: ssh.trust.verify
ssh.trust.verify: ## Show known_hosts fingerprints for HOST=...
	@test -n "$(HOST)" || (echo "ERROR: HOST is required (e.g. make ssh.trust.verify HOST=192.0.2.10)"; exit 1)
	bash "$(OPS_SCRIPTS_DIR)/ssh-trust-verify.sh" --host "$(HOST)"

.PHONY: ops.replace.inplace
ops.replace.inplace: ## Runbook pointer: replace/recreate same VMID (no auto-apply)
	@echo "Replace (in-place VMID) guidance:"
	@echo "- Edit ENV=$(ENV) template pin (fabric-core/terraform/envs/$(ENV)/main.tf lxc_rootfs_version)"
	@echo "- Run: make tf.plan ENV=$(ENV)"
	@echo "- Apply deliberately: make tf.apply ENV=$(ENV)"
	@echo "- Then: make ansible.bootstrap ENV=$(ENV) && make ansible.harden ENV=$(ENV)"
	@echo "- Validate: ssh samakia@<ip> succeeds; ssh root@<ip> fails"
	@echo "- SSH trust rotation: make ssh.trust.rotate HOST=<ip> (optionally enroll after out-of-band verification)"

.PHONY: ops.bluegreen.plan
ops.bluegreen.plan: ## Runbook pointer: blue/green CT replacement (no auto-apply)
	@echo "Blue/green guidance (new VMID + cutover):"
	@echo "- Add a new module instance with a new VMID + new MAC reservation"
	@echo "- Apply: make tf.apply ENV=$(ENV)"
	@echo "- Bootstrap + harden the new CT (root-only then samakia)"
	@echo "- Cut over traffic at the application ingress layer (no DNS dependency assumed)"
	@echo "- Decommission old CT via Git change + apply"

.PHONY: phase1.accept
phase1.accept: ## Run Phase 1 acceptance suite (ENV=...; CI-safe; no prompts)
	ENV="$(ENV)" bash "$(OPS_SCRIPTS_DIR)/phase1-accept.sh"

.PHONY: policy.check
policy.check: ## Run policy-as-code gates (terraform + secrets + HA + docs)
	@bash "$(POLICY_DIR)/policy.sh"

.PHONY: exposure.policy.check
exposure.policy.check: ## Validate exposure policy (Phase 13 Part 1)
	@bash "$(REPO_ROOT)/ops/exposure/policy/validate.sh"

.PHONY: exposure.plan
exposure.plan: ## Exposure plan (read-only) (TENANT=<id> WORKLOAD=<id> ENV=<env>)
	@TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" ENV="$(ENV)" \
		bash "$(REPO_ROOT)/ops/exposure/plan/plan.sh" --tenant "$(TENANT)" --workload "$(WORKLOAD)" --env "$(ENV)"

.PHONY: exposure.plan.explain
exposure.plan.explain: ## Explain exposure policy decision (TENANT=<id> WORKLOAD=<id> ENV=<env>)
	@TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" ENV="$(ENV)" \
		bash "$(REPO_ROOT)/ops/exposure/policy/explain.sh" \
		--tenant "$(TENANT)" --workload "$(WORKLOAD)" --env "$(ENV)" \
		--binding "$(REPO_ROOT)/artifacts/bindings/$(TENANT)/$(WORKLOAD)/connection.json"

.PHONY: exposure.approve
exposure.approve: ## Approve exposure (guarded) (TENANT=<id> WORKLOAD=<id> ENV=<env>)
	@TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" ENV="$(ENV)" \
		APPROVER_ID="$(APPROVER_ID)" EXPOSE_REASON="$(EXPOSE_REASON)" PLAN_EVIDENCE_REF="$(PLAN_EVIDENCE_REF)" \
		CHANGE_WINDOW_START="$(CHANGE_WINDOW_START)" CHANGE_WINDOW_END="$(CHANGE_WINDOW_END)" CHANGE_WINDOW_ID="$(CHANGE_WINDOW_ID)" \
		EXPOSE_SIGN="$(EXPOSE_SIGN)" EVIDENCE_SIGN_KEY="$(EVIDENCE_SIGN_KEY)" \
		APPROVAL_INPUT="$(APPROVAL_INPUT)" APPROVAL_ALLOW_CI="$(APPROVAL_ALLOW_CI)" \
		bash "$(REPO_ROOT)/ops/exposure/approve/approve.sh" --tenant "$(TENANT)" --workload "$(WORKLOAD)" --env "$(ENV)"

.PHONY: exposure.apply
exposure.apply: ## Apply exposure artifacts (guarded) (TENANT=<id> WORKLOAD=<id> ENV=<env>)
	@TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" ENV="$(ENV)" \
		APPROVAL_DIR="$(APPROVAL_DIR)" APPROVAL_PATH="$(APPROVAL_PATH)" PLAN_EVIDENCE_REF="$(PLAN_EVIDENCE_REF)" \
		EXPOSE_EXECUTE="$(EXPOSE_EXECUTE)" EXPOSE_REASON="$(EXPOSE_REASON)" APPROVER_ID="$(APPROVER_ID)" \
		CHANGE_WINDOW_START="$(CHANGE_WINDOW_START)" CHANGE_WINDOW_END="$(CHANGE_WINDOW_END)" CHANGE_WINDOW_MAX_MINUTES="$(CHANGE_WINDOW_MAX_MINUTES)" \
		EXPOSE_SIGN="$(EXPOSE_SIGN)" EVIDENCE_SIGN_KEY="$(EVIDENCE_SIGN_KEY)" \
		bash "$(REPO_ROOT)/ops/exposure/apply/apply.sh" --tenant "$(TENANT)" --workload "$(WORKLOAD)" --env "$(ENV)"

.PHONY: exposure.verify
exposure.verify: ## Verify exposure (read-only; live mode guarded) (TENANT=<id> WORKLOAD=<id> ENV=<env>)
	@TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" ENV="$(ENV)" VERIFY_LIVE="$(VERIFY_LIVE)" \
		EXPOSE_SIGN="$(EXPOSE_SIGN)" EVIDENCE_SIGN_KEY="$(EVIDENCE_SIGN_KEY)" \
		bash "$(REPO_ROOT)/ops/exposure/verify/verify.sh" --tenant "$(TENANT)" --workload "$(WORKLOAD)" --env "$(ENV)"

.PHONY: exposure.rollback
exposure.rollback: ## Rollback exposure artifacts (guarded) (TENANT=<id> WORKLOAD=<id> ENV=<env>)
	@TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" ENV="$(ENV)" \
		ROLLBACK_EXECUTE="$(ROLLBACK_EXECUTE)" ROLLBACK_REASON="$(ROLLBACK_REASON)" ROLLBACK_REQUESTED_BY="$(ROLLBACK_REQUESTED_BY)" \
		CHANGE_WINDOW_START="$(CHANGE_WINDOW_START)" CHANGE_WINDOW_END="$(CHANGE_WINDOW_END)" CHANGE_WINDOW_MAX_MINUTES="$(CHANGE_WINDOW_MAX_MINUTES)" \
		EXPOSE_SIGN="$(EXPOSE_SIGN)" EVIDENCE_SIGN_KEY="$(EVIDENCE_SIGN_KEY)" \
		bash "$(REPO_ROOT)/ops/exposure/rollback/rollback.sh" --tenant "$(TENANT)" --workload "$(WORKLOAD)" --env "$(ENV)"

.PHONY: secrets.doctor
secrets.doctor: ## Show secrets backend configuration (no secrets)
	@bash "$(REPO_ROOT)/ops/secrets/secrets.sh" doctor

.PHONY: ssh.keys.generate
ssh.keys.generate: ## Generate a new local SSH keypair (NAME=... optional)
	@bash "$(REPO_ROOT)/ops/security/ssh/ssh-keys-generate.sh" --name "$(NAME)"

.PHONY: ssh.keys.dryrun
ssh.keys.dryrun: ## SSH key rotation dry-run (read-only)
	@bash "$(REPO_ROOT)/ops/security/ssh/ssh-keys-dryrun.sh"

.PHONY: ssh.keys.rotate
ssh.keys.rotate: ## SSH key rotation (requires ROTATE_EXECUTE=1; BREAK_GLASS/I_UNDERSTAND optional)
	@bash "$(REPO_ROOT)/ops/security/ssh/ssh-keys-rotate.sh" --execute

.PHONY: firewall.check
firewall.check: ## Firewall profile integrity check (default-off)
	@bash "$(REPO_ROOT)/ops/security/firewall/firewall-check.sh"

.PHONY: firewall.dryrun
firewall.dryrun: ## Firewall profile dry-run (syntax check)
	@bash "$(REPO_ROOT)/ops/security/firewall/firewall-dryrun.sh"

.PHONY: firewall.apply
firewall.apply: ## Apply firewall profile (requires FIREWALL_ENABLE=1 FIREWALL_EXECUTE=1)
	@bash "$(REPO_ROOT)/ops/security/firewall/firewall-apply.sh"

.PHONY: compliance.eval
compliance.eval: ## Evaluate compliance profile (PROFILE=baseline|hardened)
	@bash "$(REPO_ROOT)/ops/scripts/compliance-eval.sh" --profile "$(PROFILE)"

.PHONY: phase2.accept
phase2.accept: ## Run Phase 2 acceptance suite (read-only; DNS + MinIO planes)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		bash "$(FABRIC_CI_DIR)/lint.sh"; \
		bash "$(FABRIC_CI_DIR)/validate.sh"; \
		$(MAKE) dns.sdn.accept ENV=samakia-dns; \
		$(MAKE) dns.accept; \
		$(MAKE) minio.sdn.accept ENV=samakia-minio; \
		$(MAKE) minio.converged.accept ENV=samakia-minio; \
		$(MAKE) minio.quorum.guard ENV=samakia-minio; \
		$(MAKE) minio.backend.smoke ENV=samakia-minio; \
	'

.PHONY: phase2.1.entry.check
phase2.1.entry.check: ## Phase 2.1 entry checklist (writes acceptance/PHASE2_1_ENTRY_CHECKLIST.md)
	@bash "$(OPS_SCRIPTS_DIR)/phase2-1-entry-check.sh"

.PHONY: phase5.entry.check
phase5.entry.check: ## Phase 5 entry checklist (writes acceptance/PHASE5_ENTRY_CHECKLIST.md)
	@bash "$(OPS_SCRIPTS_DIR)/phase5-entry-check.sh"

.PHONY: phase5.accept
phase5.accept: ## Run Phase 5 acceptance suite (read-only)
	@bash "$(OPS_SCRIPTS_DIR)/phase5-accept.sh"

.PHONY: phase6.entry.check
phase6.entry.check: ## Phase 6 entry checklist (writes acceptance/PHASE6_ENTRY_CHECKLIST.md)
	@bash "$(OPS_SCRIPTS_DIR)/phase6-entry-check.sh"

.PHONY: tenants.schema.validate
tenants.schema.validate: ## Validate tenant contracts (schema only)
	@bash "$(REPO_ROOT)/ops/tenants/validate-schema.sh"

.PHONY: tenants.semantics.validate
tenants.semantics.validate: ## Validate tenant contracts (semantics only)
	@bash "$(REPO_ROOT)/ops/tenants/validate-semantics.sh"

.PHONY: tenants.validate
tenants.validate: ## Validate tenant contracts (schema + semantics)
	@bash "$(REPO_ROOT)/ops/tenants/validate.sh"

.PHONY: tenants.evidence
tenants.evidence: ## Generate tenant evidence packets (TENANT=all or id)
	@TENANT="$(TENANT)" bash "$(REPO_ROOT)/ops/tenants/evidence.sh"

.PHONY: tenants.doctor
tenants.doctor: ## Check tenant tooling and contract presence
	@bash "$(REPO_ROOT)/ops/tenants/tenants.sh" doctor

.PHONY: tenants.execute.policy.check
tenants.execute.policy.check: ## Validate tenant execute policy (allowlists + guards)
	@bash "$(REPO_ROOT)/ops/tenants/execute/validate-execute-policy.sh"

.PHONY: tenants.plan
tenants.plan: ## Dry-run tenant enablement plan (TENANT=<id> ENV=<env> EXECUTE_REASON=...)
	@TENANT="$(TENANT)" ENV="$(ENV)" EXECUTE_REASON="$(EXECUTE_REASON)" \
		bash "$(REPO_ROOT)/ops/tenants/execute/plan.sh" --tenant "$(TENANT)" --env "$(ENV)"

.PHONY: tenants.apply
tenants.apply: ## Apply tenant enablement (guarded) (TENANT=<id> ENV=<env>)
	@TENANT="$(TENANT)" ENV="$(ENV)" \
		bash "$(REPO_ROOT)/ops/tenants/execute/apply.sh" --tenant "$(TENANT)" --env "$(ENV)"

.PHONY: tenants.creds.issue
tenants.creds.issue: ## Issue tenant credentials (guarded) (TENANT=<id> CONSUMER=<name> ENDPOINT_REF=...)
	@TENANT="$(TENANT)" CONSUMER="$(CONSUMER)" ENDPOINT_REF="$(ENDPOINT_REF)" \
		bash "$(REPO_ROOT)/ops/tenants/creds/issue.sh" --tenant "$(TENANT)" --consumer "$(CONSUMER)" --endpoint "$(ENDPOINT_REF)"

.PHONY: tenants.dr.validate
tenants.dr.validate: ## Validate tenant DR testcases wiring
	@bash "$(REPO_ROOT)/ops/tenants/dr/validate-dr.sh"

.PHONY: tenants.dr.run
tenants.dr.run: ## Run tenant DR harness (dry-run default) (TENANT=<id> ENV=<env> DR_MODE=execute)
	@TENANT="$(TENANT)" ENV="$(ENV)" DR_MODE="$(DR_MODE)" \
		bash "$(REPO_ROOT)/ops/tenants/dr/run.sh" --tenant "$(TENANT)" --mode "$${DR_MODE:-dry-run}"

.PHONY: substrate.contracts.validate
substrate.contracts.validate: ## Validate substrate enabled contracts (design-only)
	@bash "$(REPO_ROOT)/ops/substrate/validate.sh"

.PHONY: tenants.capacity.validate
tenants.capacity.validate: ## Validate tenant capacity contracts (schema + semantics)
	@bash "$(REPO_ROOT)/ops/substrate/capacity/validate-capacity-schema.sh"
	@bash "$(REPO_ROOT)/ops/substrate/capacity/validate-capacity-semantics.sh"

.PHONY: substrate.capacity.guard
substrate.capacity.guard: ## Evaluate capacity guard (contract-only) (TENANT=<id|all>)
	@TENANT="$(TENANT)" bash "$(REPO_ROOT)/ops/substrate/capacity/capacity-guard.sh"

.PHONY: substrate.capacity.evidence
substrate.capacity.evidence: ## Generate capacity guard evidence (TENANT=<id|all>)
	@TENANT="$(TENANT)" bash "$(REPO_ROOT)/ops/substrate/capacity/capacity-evidence.sh"

.PHONY: substrate.plan
substrate.plan: ## Generate tenant substrate plan (read-only) (TENANT=<id|all>)
	@TENANT="$(TENANT)" bash "$(REPO_ROOT)/ops/substrate/substrate.sh" plan "TENANT=$${TENANT:-all}"

.PHONY: substrate.dr.dryrun
substrate.dr.dryrun: ## Generate tenant substrate DR dry-run plan (read-only) (TENANT=<id|all>)
	@TENANT="$(TENANT)" bash "$(REPO_ROOT)/ops/substrate/substrate.sh" dr-dryrun "TENANT=$${TENANT:-all}"

.PHONY: substrate.apply
substrate.apply: ## Apply tenant substrate enablement (guarded) (TENANT=<id|all> ENV=<env>)
	@TENANT="$(TENANT)" ENV="$(ENV)" bash "$(REPO_ROOT)/ops/substrate/substrate.sh" apply "TENANT=$${TENANT:-all}"

.PHONY: substrate.verify
substrate.verify: ## Verify tenant substrate endpoints (read-only) (TENANT=<id|all>)
	@TENANT="$(TENANT)" bash "$(REPO_ROOT)/ops/substrate/substrate.sh" verify "TENANT=$${TENANT:-all}"

.PHONY: substrate.dr.execute
substrate.dr.execute: ## Execute tenant substrate DR (guarded) (TENANT=<id|all> ENV=<env>)
	@TENANT="$(TENANT)" ENV="$(ENV)" bash "$(REPO_ROOT)/ops/substrate/substrate.sh" dr-execute "TENANT=$${TENANT:-all}"

.PHONY: substrate.doctor
substrate.doctor: ## Check substrate plan tooling and contracts
	@bash "$(REPO_ROOT)/ops/substrate/substrate.sh" doctor

.PHONY: substrate.plan.ci
substrate.plan.ci: ## CI-safe substrate plan (examples only; no persistence)
	@CI=1 TENANT=all bash "$(REPO_ROOT)/ops/substrate/substrate.sh" plan "TENANT=$${TENANT:-all}"

.PHONY: substrate.observe
substrate.observe: ## Observe substrate runtime (read-only) (TENANT=<id|all>)
	@TENANT="$(TENANT)" bash "$(REPO_ROOT)/ops/substrate/observe/observe.sh"

.PHONY: substrate.observe.compare
substrate.observe.compare: ## Compare declared vs observed substrate state (read-only) (TENANT=<id|all>)
	@TENANT="$(TENANT)" bash "$(REPO_ROOT)/ops/substrate/observe/compare.sh"

.PHONY: substrate.observe.evidence
substrate.observe.evidence: ## Generate substrate observability evidence (read-only) (TENANT=<id|all>)
	@TENANT="$(TENANT)" bash "$(REPO_ROOT)/ops/substrate/observe/compare.sh"

.PHONY: substrate.alert.validate
substrate.alert.validate: ## Validate drift alert routing defaults (read-only)
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(REPO_ROOT)/ops/substrate/alert/validate-routing.sh"

.PHONY: phase10.entry.check
phase10.entry.check: ## Phase 10 entry checklist (writes acceptance/PHASE10_ENTRY_CHECKLIST.md)
	@bash "$(OPS_SCRIPTS_DIR)/phase10-entry-check.sh"

.PHONY: phase10.part1.entry.check
phase10.part1.entry.check: ## Phase 10 Part 1 entry checklist (writes acceptance/PHASE10_PART1_ENTRY_CHECKLIST.md)
	@bash "$(OPS_SCRIPTS_DIR)/phase10-part1-entry-check.sh"

.PHONY: phase10.part1.accept
phase10.part1.accept: ## Run Phase 10 Part 1 acceptance suite (read-only)
	@bash "$(OPS_SCRIPTS_DIR)/phase10-part1-accept.sh"

.PHONY: phase10.part2.entry.check
phase10.part2.entry.check: ## Phase 10 Part 2 entry checklist (writes acceptance/PHASE10_PART2_ENTRY_CHECKLIST.md)
	@bash "$(OPS_SCRIPTS_DIR)/phase10-part2-entry-check.sh"

.PHONY: phase10.part2.accept
phase10.part2.accept: ## Run Phase 10 Part 2 acceptance suite (read-only)
	@bash "$(OPS_SCRIPTS_DIR)/phase10-part2-accept.sh"

.PHONY: phase11.entry.check
phase11.entry.check: ## Phase 11 entry checklist (writes acceptance/PHASE11_ENTRY_CHECKLIST.md)
	@bash "$(OPS_SCRIPTS_DIR)/phase11-entry-check.sh"

.PHONY: phase11.accept
phase11.accept: ## Run Phase 11 acceptance suite (design-only, read-only)
	@bash "$(OPS_SCRIPTS_DIR)/phase11-accept.sh"

.PHONY: phase11.part1.entry.check
phase11.part1.entry.check: ## Phase 11 Part 1 entry checklist (writes acceptance/PHASE11_PART1_ENTRY_CHECKLIST.md)
	@bash "$(OPS_SCRIPTS_DIR)/phase11-part1-entry-check.sh"

.PHONY: phase11.part1.accept
phase11.part1.accept: ## Run Phase 11 Part 1 acceptance suite (plan-only, read-only)
	@bash "$(OPS_SCRIPTS_DIR)/phase11-part1-accept.sh"

.PHONY: phase11.part2.entry.check
phase11.part2.entry.check: ## Phase 11 Part 2 entry checklist (writes acceptance/PHASE11_PART2_ENTRY_CHECKLIST.md)
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(OPS_SCRIPTS_DIR)/phase11-part2-entry-check.sh"

.PHONY: phase11.part2.accept
phase11.part2.accept: ## Run Phase 11 Part 2 acceptance suite (guarded, read-only in CI)
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(OPS_SCRIPTS_DIR)/phase11-part2-accept.sh"

.PHONY: phase11.part3.entry.check
phase11.part3.entry.check: ## Phase 11 Part 3 entry checklist (writes acceptance/PHASE11_PART3_ENTRY_CHECKLIST.md)
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(OPS_SCRIPTS_DIR)/phase11-part3-entry-check.sh"

.PHONY: phase11.part3.accept
phase11.part3.accept: ## Run Phase 11 Part 3 acceptance suite (capacity guardrails, read-only)
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(OPS_SCRIPTS_DIR)/phase11-part3-accept.sh"

.PHONY: phase11.part4.entry.check
phase11.part4.entry.check: ## Phase 11 Part 4 entry checklist (writes acceptance/PHASE11_PART4_ENTRY_CHECKLIST.md)
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(OPS_SCRIPTS_DIR)/phase11-part4-entry-check.sh"

.PHONY: phase11.part4.accept
phase11.part4.accept: ## Run Phase 11 Part 4 acceptance suite (observability, read-only)
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(OPS_SCRIPTS_DIR)/phase11-part4-accept.sh"

.PHONY: phase11.part5.entry.check
phase11.part5.entry.check: ## Phase 11 Part 5 entry checklist (writes acceptance/PHASE11_PART5_ENTRY_CHECKLIST.md)
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(OPS_SCRIPTS_DIR)/phase11-part5-entry-check.sh"

.PHONY: phase11.part5.routing.accept
phase11.part5.routing.accept: ## Run Phase 11 Part 5 routing defaults acceptance (read-only)
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(OPS_SCRIPTS_DIR)/phase11-part5-routing-accept.sh"

.PHONY: phase11.hardening.entry.check
phase11.hardening.entry.check: ## Phase 11 pre-exposure hardening entry checklist (writes acceptance/PHASE11_HARDENING_ENTRY_CHECKLIST.md)
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(OPS_SCRIPTS_DIR)/phase11-hardening-entry-check.sh"

.PHONY: phase11.hardening.accept
phase11.hardening.accept: ## Run Phase 11 pre-exposure hardening gate (read-only)
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(OPS_SCRIPTS_DIR)/phase11-hardening-accept.sh"

.PHONY: hardening.checklist.validate
hardening.checklist.validate: ## Validate and evaluate the hardening checklist (JSON source of truth)
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(REPO_ROOT)/hardening/validate/checklist-validate.sh"

.PHONY: hardening.checklist.render
hardening.checklist.render: hardening.checklist.validate ## Render hardening checklist markdown from JSON
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(REPO_ROOT)/hardening/render/checklist-to-md.sh"

.PHONY: hardening.checklist.summary
hardening.checklist.summary: hardening.checklist.validate ## Emit hardening checklist summary (JSON) and fail on hard failures
	@FABRIC_REPO_ROOT="$(FABRIC_REPO_ROOT)" bash "$(REPO_ROOT)/hardening/render/checklist-to-summary.sh"

.PHONY: consumers.validate
consumers.validate: ## Validate consumer contracts (schema + semantics)
	@bash "$(REPO_ROOT)/ops/consumers/validate/validate-consumers.sh"

.PHONY: consumers.ha.check
consumers.ha.check: ## Validate consumer HA readiness (contract-level)
	@bash "$(REPO_ROOT)/ops/consumers/validate/validate-ha-ready.sh"

.PHONY: consumers.disaster.check
consumers.disaster.check: ## Validate consumer disaster coverage wiring
	@bash "$(REPO_ROOT)/ops/consumers/disaster/validate-disaster-coverage.sh"

.PHONY: consumers.evidence
consumers.evidence: ## Generate consumer readiness evidence packets (read-only)
	@bash "$(REPO_ROOT)/ops/consumers/evidence/consumer-readiness.sh"

.PHONY: consumers.gameday.mapping.check
consumers.gameday.mapping.check: ## Validate GameDay mapping for consumer testcases
	@bash "$(REPO_ROOT)/ops/consumers/disaster/validate-gameday-mapping.sh"

.PHONY: consumers.gameday.execute.policy.check
consumers.gameday.execute.policy.check: ## Validate execute-mode GameDay policy (allowlists + signing)
	@bash "$(REPO_ROOT)/ops/consumers/disaster/validate-execute-policy.sh"

.PHONY: consumers.gameday.dryrun
consumers.gameday.dryrun: ## Dry-run a deterministic GameDay per consumer type
	@bash "$(REPO_ROOT)/ops/consumers/disaster/consumer-gameday.sh" \
		--consumer "$(REPO_ROOT)/contracts/consumers/kubernetes/ready.yml" \
		--testcase "gameday:vip-failover" --dry-run
	@bash "$(REPO_ROOT)/ops/consumers/disaster/consumer-gameday.sh" \
		--consumer "$(REPO_ROOT)/contracts/consumers/database/ready.yml" \
		--testcase "gameday:service-restart" --dry-run
	@bash "$(REPO_ROOT)/ops/consumers/disaster/consumer-gameday.sh" \
		--consumer "$(REPO_ROOT)/contracts/consumers/message-queue/ready.yml" \
		--testcase "gameday:vip-failover" --dry-run
	@bash "$(REPO_ROOT)/ops/consumers/disaster/consumer-gameday.sh" \
		--consumer "$(REPO_ROOT)/contracts/consumers/cache/ready.yml" \
		--testcase "gameday:service-restart" --dry-run

.PHONY: consumers.bundle
consumers.bundle: ## Generate consumer bundle outputs (read-only)
	@bash "$(REPO_ROOT)/ops/consumers/provision/consumer-bundle.sh"

.PHONY: consumers.bundle.check
consumers.bundle.check: ## Validate consumer bundle outputs
	@bash "$(REPO_ROOT)/ops/consumers/provision/consumer-bundle-validate.sh"

.PHONY: phase6.part1.accept
phase6.part1.accept: ## Run Phase 6 Part 1 acceptance (read-only consumer contracts)
	@bash "$(OPS_SCRIPTS_DIR)/phase6-part1-accept.sh"

.PHONY: phase6.part2.accept
phase6.part2.accept: ## Run Phase 6 Part 2 acceptance (read-only, dry-run gamedays)
	@bash "$(OPS_SCRIPTS_DIR)/phase6-part2-accept.sh"

.PHONY: phase6.part3.accept
phase6.part3.accept: ## Run Phase 6 Part 3 acceptance (read-only; validate execute guards)
	@bash "$(OPS_SCRIPTS_DIR)/phase6-part3-accept.sh"

.PHONY: ai.plan.review
ai.plan.review: ## Run AI plan review packet (read-only; PLAN_PATH required)
	@ENV="$(ENV)" bash "$(REPO_ROOT)/ops/ai/plan-review/plan-review.sh" --plan "$(PLAN_PATH)" --env "$(ENV)"

.PHONY: ai.runbook.check
ai.runbook.check: ## Validate AI runbook formatting (read-only)
	@bash "$(OPS_SCRIPTS_DIR)/ai-runbook-check.sh"

.PHONY: ai.safe.index.check
ai.safe.index.check: ## Validate 03:00-safe allowlist index (read-only)
	@bash "$(OPS_SCRIPTS_DIR)/ai-safe-index-check.sh"

.PHONY: phase7.entry.check
phase7.entry.check: ## Phase 7 entry checklist (writes acceptance/PHASE7_ENTRY_CHECKLIST.md)
	@bash "$(OPS_SCRIPTS_DIR)/phase7-entry-check.sh"

.PHONY: phase8.entry.check
phase8.entry.check: ## Phase 8 entry checklist (writes acceptance/PHASE8_ENTRY_CHECKLIST.md)
	@bash "$(OPS_SCRIPTS_DIR)/phase8-entry-check.sh"

.PHONY: phase7.accept
phase7.accept: ## Run Phase 7 acceptance suite (read-only)
	@bash "$(OPS_SCRIPTS_DIR)/phase7-accept.sh"

.PHONY: ai.accept
ai.accept: ## Run Phase 7 acceptance suite (read-only)
	@bash "$(OPS_SCRIPTS_DIR)/phase7-accept.sh"

.PHONY: phase2.1.accept
phase2.1.accept: ## Run Phase 2.1 acceptance suite (read-only; shared control-plane services)
	@ENV="$(ENV)" bash "$(OPS_SCRIPTS_DIR)/phase2-1-accept.sh"

.PHONY: phase2.2.entry.check
phase2.2.entry.check: ## Phase 2.2 entry checklist (writes acceptance/PHASE2_2_ENTRY_CHECKLIST.md)
	@bash "$(OPS_SCRIPTS_DIR)/phase2-2-entry-check.sh"

.PHONY: phase2.2.accept
phase2.2.accept: ## Run Phase 2.2 acceptance suite (read-only; control-plane invariants)
	@ENV="$(ENV)" bash "$(OPS_SCRIPTS_DIR)/phase2-2-accept.sh"

.PHONY: phase4.entry.check
phase4.entry.check: ## Phase 4 entry checklist (writes acceptance/PHASE4_ENTRY_CHECKLIST.md)
	@bash "$(OPS_SCRIPTS_DIR)/phase4-entry-check.sh"

.PHONY: phase4.accept
phase4.accept: ## Run Phase 4 acceptance suite (policy + CI parity + evidence packets)
	@bash "$(OPS_SCRIPTS_DIR)/phase4-accept.sh"

.PHONY: ha.placement.validate
ha.placement.validate: ## HA placement validation (read-only; uses placement policy + inventory)
	@if [[ -n "$(ENV)" ]]; then \
		FABRIC_TERRAFORM_ENV="$(ENV)" bash "$(OPS_SCRIPTS_DIR)/ha/placement-validate.sh" --env "$(ENV)"; \
	else \
		bash "$(OPS_SCRIPTS_DIR)/ha/placement-validate.sh" --all; \
	fi

.PHONY: ha.proxmox.audit
ha.proxmox.audit: ## Proxmox HA audit (read-only; ensures policy alignment)
	@bash "$(OPS_SCRIPTS_DIR)/ha/proxmox-ha-audit.sh"

.PHONY: ha.enforce.check
ha.enforce.check: ## HA enforcement check (placement + Proxmox HA; blocks on violations unless overridden)
	@ENV="$(ENV)" bash "$(OPS_SCRIPTS_DIR)/ha/enforce-placement.sh" --env "$(ENV)"
	@ENV="$(ENV)" bash "$(OPS_SCRIPTS_DIR)/ha/proxmox-ha-audit.sh" --enforce --env "$(ENV)"

.PHONY: ha.evidence.snapshot
ha.evidence.snapshot: ## HA evidence snapshot (read-only; writes artifacts/ha-evidence/<UTC>/report.md)
	@bash "$(OPS_SCRIPTS_DIR)/ha/evidence-snapshot.sh"

.PHONY: phase3.part1.accept
phase3.part1.accept: ## Run Phase 3 Part 1 acceptance (HA semantics + failure domains)
	@pre-commit run --all-files
	@bash "fabric-ci/scripts/lint.sh"
	@bash "fabric-ci/scripts/validate.sh"
	@$(MAKE) ha.placement.validate ENV="$(ENV)"
	@$(MAKE) ha.proxmox.audit
	@$(MAKE) ha.evidence.snapshot

.PHONY: phase3.part3.accept
phase3.part3.accept: ## Run Phase 3 Part 3 acceptance (HA enforcement)
	@pre-commit run --all-files
	@bash "fabric-ci/scripts/lint.sh"
	@bash "fabric-ci/scripts/validate.sh"
	@$(MAKE) ha.enforce.check ENV="$(ENV)"
	@bash "$(OPS_SCRIPTS_DIR)/ha/test-enforce-placement.sh"

.PHONY: gameday.precheck
gameday.precheck: ## GameDay precheck (read-only)
	@bash "$(OPS_SCRIPTS_DIR)/gameday/gameday-precheck.sh"

.PHONY: gameday.evidence
gameday.evidence: ## GameDay evidence snapshot (baseline)
	@bash "$(OPS_SCRIPTS_DIR)/gameday/gameday-evidence.sh" --id "$(GAMEDAY_ID)" --tag baseline

.PHONY: gameday.vip.failover.dry
gameday.vip.failover.dry: ## GameDay VIP failover dry-run (no execution)
	@VIP_GROUP="$(VIP_GROUP)" bash "$(OPS_SCRIPTS_DIR)/gameday/gameday-vip-failover.sh" --vip-group "$(VIP_GROUP)" --dry-run

.PHONY: gameday.service.restart.dry
gameday.service.restart.dry: ## GameDay service restart dry-run (no execution)
	@SERVICE="$(SERVICE)" TARGET="$(TARGET)" CHECK_URL="$(CHECK_URL)" bash "$(OPS_SCRIPTS_DIR)/gameday/gameday-service-restart.sh" --service "$(SERVICE)" --target "$(TARGET)" --check-url "$(CHECK_URL)" --dry-run

.PHONY: gameday.postcheck
gameday.postcheck: ## GameDay postcheck (read-only)
	@bash "$(OPS_SCRIPTS_DIR)/gameday/gameday-postcheck.sh" --id "$(GAMEDAY_ID)"

.PHONY: phase3.part2.accept
phase3.part2.accept: ## Run Phase 3 Part 2 acceptance (GameDay framework, dry-run only)
	@pre-commit run --all-files
	@bash "fabric-ci/scripts/lint.sh"
	@bash "fabric-ci/scripts/validate.sh"
	@GAMEDAY_ID="phase3-part2-$$(date -u +%Y%m%dT%H%M%SZ)"; \
		$(MAKE) gameday.precheck; \
		$(MAKE) gameday.evidence GAMEDAY_ID="$$GAMEDAY_ID"; \
		$(MAKE) gameday.vip.failover.dry VIP_GROUP="$(VIP_GROUP)"; \
		$(MAKE) gameday.service.restart.dry SERVICE="$(SERVICE)" TARGET="$(TARGET)" CHECK_URL="$(CHECK_URL)"; \
		$(MAKE) gameday.postcheck GAMEDAY_ID="$$GAMEDAY_ID"

.PHONY: phase0.accept
phase0.accept: ## Run Phase 0 acceptance suite (static checks; no infra mutations)
	bash "$(OPS_SCRIPTS_DIR)/phase0-accept.sh"

###############################################################################
# MinIO HA backend (Terraform + Ansible + acceptance)
###############################################################################

.PHONY: minio.tf.plan
minio.tf.plan: ## MinIO Terraform plan (bootstrap-local; ENV=samakia-minio)
	@test "$(ENV)" = "samakia-minio" || (echo "ERROR: set ENV=samakia-minio"; exit 2)
	@test -d "$(TERRAFORM_ENV_DIR)" || (echo "ERROR: Terraform env dir not found: $(TERRAFORM_ENV_DIR)"; exit 1)
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
			env_file="$(RUNNER_ENV_FILE)"; \
			if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
			$(MAKE) runner.env.check; \
			src_dir="$(TERRAFORM_ENV_DIR)"; \
			work_dir="$(MINIO_BOOTSTRAP_DIR)"; \
			mkdir -p "$$work_dir"; \
			rm -rf "$$work_dir/.terraform" || true; \
			rm -f "$$work_dir"/*.tf "$$work_dir"/.terraform.lock.hcl 2>/dev/null || true; \
				for f in "$$src_dir"/*.tf "$$src_dir"/.terraform.lock.hcl; do \
					base="$$(basename "$$f")"; \
					if [[ "$$base" = "backend.tf" ]]; then continue; fi; \
					cp -f "$$f" "$$work_dir/"; \
				done; \
				if [[ -s "$$src_dir/terraform.tfstate" ]]; then cp -f "$$src_dir/terraform.tfstate" "$$work_dir/terraform.tfstate"; fi; \
				if [[ -s "$$src_dir/terraform.tfstate.backup" ]]; then cp -f "$$src_dir/terraform.tfstate.backup" "$$work_dir/terraform.tfstate.backup"; fi; \
				# If terraform.tfstate is empty/incomplete but a backup exists, prefer the backup.\n\
				if [[ -s "$$work_dir/terraform.tfstate.backup" ]]; then \
					if [[ ! -s "$$work_dir/terraform.tfstate" ]] || ! grep -q "\"type\": \"proxmox_lxc\"" "$$work_dir/terraform.tfstate" 2>/dev/null; then \
						if grep -q "\"type\": \"proxmox_lxc\"" "$$work_dir/terraform.tfstate.backup" 2>/dev/null; then \
							cp -f "$$work_dir/terraform.tfstate.backup" "$$work_dir/terraform.tfstate"; \
						fi; \
					fi; \
				fi; \
				terraform -chdir="$$work_dir" init -input=false -backend=false -reconfigure >/dev/null; \
				terraform -chdir="$$work_dir" validate; \
				$(MAKE) ha.enforce.check ENV="$(ENV)"; \
				terraform -chdir="$$work_dir" plan -input=false -lock=false $(TF_PLAN_FLAGS); \
				if [[ -f "$$work_dir/terraform.tfstate" ]]; then cp -f "$$work_dir/terraform.tfstate" "$$src_dir/terraform.tfstate"; fi; \
				if [[ -f "$$work_dir/terraform.tfstate.backup" ]]; then cp -f "$$work_dir/terraform.tfstate.backup" "$$src_dir/terraform.tfstate.backup"; fi; \
			'

.PHONY: minio.tf.apply
minio.tf.apply: ## MinIO Terraform apply (bootstrap-local; ENV=samakia-minio)
	@test "$(ENV)" = "samakia-minio" || (echo "ERROR: set ENV=samakia-minio"; exit 2)
	@test -d "$(TERRAFORM_ENV_DIR)" || (echo "ERROR: Terraform env dir not found: $(TERRAFORM_ENV_DIR)"; exit 1)
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
			env_file="$(RUNNER_ENV_FILE)"; \
			if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
			$(MAKE) runner.env.check; \
			src_dir="$(TERRAFORM_ENV_DIR)"; \
			work_dir="$(MINIO_BOOTSTRAP_DIR)"; \
			mkdir -p "$$work_dir"; \
			rm -rf "$$work_dir/.terraform" || true; \
			rm -f "$$work_dir"/*.tf "$$work_dir"/.terraform.lock.hcl 2>/dev/null || true; \
				for f in "$$src_dir"/*.tf "$$src_dir"/.terraform.lock.hcl; do \
					base="$$(basename "$$f")"; \
					if [[ "$$base" = "backend.tf" ]]; then continue; fi; \
					cp -f "$$f" "$$work_dir/"; \
				done; \
				if [[ -s "$$src_dir/terraform.tfstate" ]]; then cp -f "$$src_dir/terraform.tfstate" "$$work_dir/terraform.tfstate"; fi; \
				if [[ -s "$$src_dir/terraform.tfstate.backup" ]]; then cp -f "$$src_dir/terraform.tfstate.backup" "$$work_dir/terraform.tfstate.backup"; fi; \
				# If terraform.tfstate is empty/incomplete but a backup exists, prefer the backup.\n\
				if [[ -s "$$work_dir/terraform.tfstate.backup" ]]; then \
					if [[ ! -s "$$work_dir/terraform.tfstate" ]] || ! grep -q "\"type\": \"proxmox_lxc\"" "$$work_dir/terraform.tfstate" 2>/dev/null; then \
						if grep -q "\"type\": \"proxmox_lxc\"" "$$work_dir/terraform.tfstate.backup" 2>/dev/null; then \
							cp -f "$$work_dir/terraform.tfstate.backup" "$$work_dir/terraform.tfstate"; \
						fi; \
					fi; \
				fi; \
				terraform -chdir="$$work_dir" init -input=false -backend=false -reconfigure >/dev/null; \
				terraform -chdir="$$work_dir" validate; \
				$(MAKE) ha.enforce.check ENV="$(ENV)"; \
					if [[ "$(DRY_RUN)" = "1" ]]; then \
						terraform -chdir="$$work_dir" plan -input=false -lock=false $(TF_PLAN_FLAGS); \
					else \
					auto_approve=""; \
					if [[ "$(CI)" = "1" ]]; then auto_approve="-auto-approve"; fi; \
					terraform -chdir="$$work_dir" apply -input=false -lock=false $$auto_approve $(TF_APPLY_FLAGS); \
				fi; \
				if [[ -f "$$work_dir/terraform.tfstate" ]]; then cp -f "$$work_dir/terraform.tfstate" "$$src_dir/terraform.tfstate"; fi; \
				if [[ -f "$$work_dir/terraform.tfstate.backup" ]]; then cp -f "$$work_dir/terraform.tfstate.backup" "$$src_dir/terraform.tfstate.backup"; fi; \
				# Inventory consumption during bootstrap: generate outputs JSON without initializing the remote backend.\n\
				# Write it both to the bootstrap workspace and to the env dir as a safe fallback.\n\
				if [[ "$(DRY_RUN)" != "1" ]]; then \
					terraform -chdir="$$work_dir" output -json > "$$work_dir/terraform-output.json"; \
					cp -f "$$work_dir/terraform-output.json" "$$src_dir/terraform-output.json"; \
				fi; \
				'

.PHONY: minio.tf.destroy
minio.tf.destroy: ## MinIO Terraform destroy (bootstrap-local; guarded; CONFIRM=YES)
	@test "$(ENV)" = "samakia-minio" || (echo "ERROR: set ENV=samakia-minio"; exit 2)
	@test "$(CONFIRM)" = "YES" || (echo "ERROR: destructive. Re-run with CONFIRM=YES"; exit 2)
	@test -d "$(TERRAFORM_ENV_DIR)" || (echo "ERROR: Terraform env dir not found: $(TERRAFORM_ENV_DIR)"; exit 1)
	@command -v terraform >/dev/null 2>&1 || (echo "ERROR: terraform not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
			env_file="$(RUNNER_ENV_FILE)"; \
			if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
			$(MAKE) runner.env.check; \
			src_dir="$(TERRAFORM_ENV_DIR)"; \
			work_dir="$(MINIO_BOOTSTRAP_DIR)"; \
			mkdir -p "$$work_dir"; \
			rm -rf "$$work_dir/.terraform" || true; \
			rm -f "$$work_dir"/*.tf "$$work_dir"/.terraform.lock.hcl 2>/dev/null || true; \
				for f in "$$src_dir"/*.tf "$$src_dir"/.terraform.lock.hcl; do \
					base="$$(basename "$$f")"; \
					if [[ "$$base" = "backend.tf" ]]; then continue; fi; \
					cp -f "$$f" "$$work_dir/"; \
				done; \
				if [[ -s "$$src_dir/terraform.tfstate" ]]; then cp -f "$$src_dir/terraform.tfstate" "$$work_dir/terraform.tfstate"; fi; \
				if [[ -s "$$src_dir/terraform.tfstate.backup" ]]; then cp -f "$$src_dir/terraform.tfstate.backup" "$$work_dir/terraform.tfstate.backup"; fi; \
				# If terraform.tfstate is empty/incomplete but a backup exists, prefer the backup.\n\
				if [[ -s "$$work_dir/terraform.tfstate.backup" ]]; then \
					if [[ ! -s "$$work_dir/terraform.tfstate" ]] || ! grep -q "\"type\": \"proxmox_lxc\"" "$$work_dir/terraform.tfstate" 2>/dev/null; then \
						if grep -q "\"type\": \"proxmox_lxc\"" "$$work_dir/terraform.tfstate.backup" 2>/dev/null; then \
							cp -f "$$work_dir/terraform.tfstate.backup" "$$work_dir/terraform.tfstate"; \
						fi; \
					fi; \
				fi; \
				terraform -chdir="$$work_dir" init -input=false -backend=false -reconfigure >/dev/null; \
				terraform -chdir="$$work_dir" destroy -input=false -lock=false; \
				if [[ -f "$$work_dir/terraform.tfstate" ]]; then cp -f "$$work_dir/terraform.tfstate" "$$src_dir/terraform.tfstate"; fi; \
				if [[ -f "$$work_dir/terraform.tfstate.backup" ]]; then cp -f "$$work_dir/terraform.tfstate.backup" "$$src_dir/terraform.tfstate.backup"; fi; \
			'

.PHONY: minio.ansible.apply
minio.ansible.apply: ## MinIO Ansible apply (state-backend.yml; requires bootstrap already done)
	@test "$(ENV)" = "samakia-minio" || (echo "ERROR: set ENV=samakia-minio"; exit 2)
	@test -d "$(ANSIBLE_DIR)" || (echo "ERROR: ANSIBLE_DIR not found: $(ANSIBLE_DIR)"; exit 1)
	@command -v ansible-playbook >/dev/null 2>&1 || (echo "ERROR: ansible-playbook not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		candidate="$(MINIO_BOOTSTRAP_DIR)/terraform-output.json"; \
		if [[ -f "$$candidate" ]]; then export TF_OUTPUT_PATH="$$candidate"; fi; \
		FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
			ansible-playbook -i "$(ANSIBLE_INVENTORY_PATH)" "$(ANSIBLE_DIR)/playbooks/state-backend.yml" -u "$(ANSIBLE_USER)" $(ANSIBLE_FLAGS); \
	'

.PHONY: minio.accept
minio.accept: ## MinIO acceptance (VIP TLS, HA checks, bucket checks, idempotency)
	bash "$(OPS_SCRIPTS_DIR)/minio-accept.sh"

.PHONY: minio.sdn.accept
minio.sdn.accept: ## MinIO SDN acceptance (stateful plane validation; read-only)
	@test "$(ENV)" = "samakia-minio" || (echo "ERROR: set ENV=samakia-minio"; exit 2)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) runner.env.check; \
		bash "$(OPS_SCRIPTS_DIR)/minio-sdn-accept.sh"; \
	'

.PHONY: minio.converged.accept
minio.converged.accept: ## MinIO cluster convergence acceptance (read-only; requires SDN acceptance PASS)
	@test "$(ENV)" = "samakia-minio" || (echo "ERROR: set ENV=samakia-minio"; exit 2)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) runner.env.check; \
		$(MAKE) minio.sdn.accept ENV="$(ENV)"; \
		bash "$(OPS_SCRIPTS_DIR)/minio-convergence-accept.sh"; \
		$(MAKE) minio.quorum.guard ENV="$(ENV)"; \
	'

.PHONY: minio.quorum.guard
minio.quorum.guard: ## MinIO quorum-loss guard (detect-only; blocks unsafe state writes)
	@test "$(ENV)" = "samakia-minio" || (echo "ERROR: set ENV=samakia-minio"; exit 2)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) runner.env.check; \
		set +e; \
		bash "$(OPS_SCRIPTS_DIR)/minio-quorum-guard.sh"; \
		rc="$$?"; \
		set -e; \
		if [[ "$$rc" -eq 2 && "$(ALLOW_DEGRADED)" = "1" ]]; then \
			echo "[WARN] MinIO quorum guard returned WARN; proceeding because ALLOW_DEGRADED=1 (read-only use only)" >&2; \
			exit 0; \
		fi; \
		exit "$$rc"; \
	'

.PHONY: minio.state.migrate
minio.state.migrate: ## Migrate samakia-minio state to remote backend (requires MinIO up)
	@test "$(ENV)" = "samakia-minio" || (echo "ERROR: set ENV=samakia-minio"; exit 2)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) runner.env.check; \
		$(MAKE) minio.backend.smoke ENV=samakia-minio; \
		bash "$(OPS_SCRIPTS_DIR)/minio-quorum-guard.sh"; \
		# Canonical bootstrap invariant: bootstrap state lives in the runner-local workspace.\n\
		# Before migrating to the remote backend, copy the bootstrap-local state into the env dir.\n\
		# This avoids migrating an empty/placeholder state when the env dir is already backend-initialized.\n\
		src_dir="$(TERRAFORM_ENV_DIR)"; \
		work_dir="$(MINIO_BOOTSTRAP_DIR)"; \
		if [[ -s "$$work_dir/terraform.tfstate" ]]; then cp -f "$$work_dir/terraform.tfstate" "$$src_dir/terraform.tfstate"; fi; \
		if [[ -s "$$work_dir/terraform.tfstate.backup" ]]; then cp -f "$$work_dir/terraform.tfstate.backup" "$$src_dir/terraform.tfstate.backup"; fi; \
		bash "$(OPS_SCRIPTS_DIR)/tf-backend-init.sh" "$(ENV)" --migrate; \
	'

.PHONY: minio.up
minio.up: ## One-command MinIO backend deployment (tf apply -> bootstrap -> state-backend -> acceptance -> state migrate)
	@bash -euo pipefail -c '\
				if [[ "$(ENV)" != "samakia-minio" ]]; then echo "ERROR: set ENV=samakia-minio" >&2; exit 2; fi; \
			env_file="$(RUNNER_ENV_FILE)"; \
			if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
			$(MAKE) runner.env.check; \
			if [[ "$(DRY_RUN)" = "1" ]]; then \
				echo "DRY_RUN=1: planning only (no backend.configure, no terraform apply, no ansible, no migration)"; \
				$(MAKE) minio.tf.plan; \
				$(MAKE) minio.tf.apply DRY_RUN=1 CI=1; \
				exit 0; \
			fi; \
			# Proxmox SDN config must be applied before SDN-backed bridges are usable.\n\
			# This is safe/idempotent and required for first bootstrap.\n\
			bash "$(OPS_SCRIPTS_DIR)/proxmox-sdn-ensure-stateful-plane.sh" --apply; \
			$(MAKE) backend.configure; \
			$(MAKE) minio.tf.plan; \
			$(MAKE) minio.tf.apply CI=1; \
			bash "$(OPS_SCRIPTS_DIR)/proxmox-lxc-ensure-running.sh" "$(ENV)"; \
			$(MAKE) inventory.check ENV="$(ENV)"; \
			# Bootstrap must be staged for VLAN-only nodes behind jump hosts.\n\
			# Phase 1: bootstrap edges (if root SSH still enabled).\n\
			edges_bootstrap_needed=0; \
			for ip in 192.168.11.102 192.168.11.103; do \
				if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "root@$$ip" true >/dev/null 2>&1; then edges_bootstrap_needed=1; fi; \
			done; \
			if [[ "$$edges_bootstrap_needed" -eq 1 ]]; then \
				ANSIBLE_FLAGS="$(ANSIBLE_FLAGS) --limit minio-edge-*" $(MAKE) ansible.bootstrap ENV="$(ENV)"; \
			fi; \
			# Phase 2: bootstrap VLAN-only MinIO nodes via edge ProxyJump.\n\
			# Use a reachable edge as jump host (root SSH may already be disabled on edges).\n\
			jump=""; \
			for ip in 192.168.11.102 192.168.11.103; do \
				if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "samakia@$$ip" true >/dev/null 2>&1; then jump="samakia@$$ip"; break; fi; \
			done; \
			if [[ -z "$$jump" ]]; then echo "ERROR: cannot reach any MinIO edge as samakia (192.168.11.102/103); bootstrap cannot proceed" >&2; exit 1; fi; \
			nodes_need_bootstrap=0; \
			for ip in 10.10.140.11 10.10.140.12 10.10.140.13; do \
				if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new -o ProxyJump="$$jump" "root@$$ip" true >/dev/null 2>&1; then nodes_need_bootstrap=1; fi; \
			done; \
			if [[ "$$nodes_need_bootstrap" -eq 1 ]]; then \
				ANSIBLE_FLAGS="$(ANSIBLE_FLAGS) --limit minio-1,minio-2,minio-3" $(MAKE) ansible.bootstrap ENV="$(ENV)"; \
			fi; \
				$(MAKE) minio.ansible.apply; \
					$(MAKE) minio.accept; \
					bash "$(OPS_SCRIPTS_DIR)/minio-quorum-guard.sh"; \
						$(MAKE) minio.state.migrate; \
					'

.PHONY: minio.failure.sim
minio.failure.sim: ## MinIO edge failure simulation (reversible; requires EDGE=minio-edge-1|minio-edge-2)
	@test "$(ENV)" = "samakia-minio" || (echo "ERROR: set ENV=samakia-minio"; exit 2)
	@test -n "$(EDGE)" || (echo "ERROR: set EDGE=minio-edge-1|minio-edge-2"; exit 2)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) runner.env.check; \
		bash "$(OPS_SCRIPTS_DIR)/proxmox-sdn-ensure-stateful-plane.sh" --check-only; \
		$(MAKE) minio.accept ENV="$(ENV)"; \
		$(MAKE) minio.converged.accept ENV="$(ENV)"; \
		EDGE="$(EDGE)" ENV="$(ENV)" bash "$(OPS_SCRIPTS_DIR)/minio-edge-failure-sim.sh"; \
		$(MAKE) minio.sdn.accept ENV="$(ENV)"; \
		$(MAKE) minio.accept ENV="$(ENV)"; \
		$(MAKE) minio.converged.accept ENV="$(ENV)"; \
	'

.PHONY: minio.backend.smoke
minio.backend.smoke: ## MinIO Terraform backend smoke test (real init+plan against S3 backend; no apply)
	@test "$(ENV)" = "samakia-minio" || (echo "ERROR: set ENV=samakia-minio"; exit 2)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) runner.env.check; \
		bash "$(OPS_SCRIPTS_DIR)/minio-terraform-backend-smoke.sh"; \
	'

###############################################################################
# DNS infrastructure (Terraform + Ansible + acceptance)
###############################################################################

.PHONY: dns.tf.plan
dns.tf.plan: ## DNS Terraform plan (ENV=samakia-dns)
	@test "$(ENV)" = "samakia-dns" || (echo "ERROR: set ENV=samakia-dns"; exit 2)
	ENV="$(ENV)" $(MAKE) tf.plan CI=1

.PHONY: dns.tf.apply
dns.tf.apply: ## DNS Terraform apply (ENV=samakia-dns)
	@test "$(ENV)" = "samakia-dns" || (echo "ERROR: set ENV=samakia-dns"; exit 2)
	ENV="$(ENV)" $(MAKE) tf.apply CI=1

.PHONY: dns.tf.destroy
dns.tf.destroy: ## DNS Terraform destroy (guarded; CONFIRM=YES)
	@test "$(ENV)" = "samakia-dns" || (echo "ERROR: set ENV=samakia-dns"; exit 2)
	@test "$(CONFIRM)" = "YES" || (echo "ERROR: destructive. Re-run with CONFIRM=YES"; exit 2)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) tf.backend.init ENV="$(ENV)"; \
		terraform -chdir="$(REPO_ROOT)/fabric-core/terraform/envs/$(ENV)" destroy -input=false -lock-timeout="$(TF_LOCK_TIMEOUT)"; \
	'

.PHONY: dns.ansible.apply
dns.ansible.apply: ## DNS Ansible apply (dns.yml orchestrator; requires bootstrap already done)
	@test "$(ENV)" = "samakia-dns" || (echo "ERROR: set ENV=samakia-dns"; exit 2)
	@test -d "$(ANSIBLE_DIR)" || (echo "ERROR: ANSIBLE_DIR not found: $(ANSIBLE_DIR)"; exit 1)
	@command -v ansible-playbook >/dev/null 2>&1 || (echo "ERROR: ansible-playbook not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
			ansible-playbook -i "$(ANSIBLE_INVENTORY_PATH)" "$(ANSIBLE_DIR)/playbooks/dns.yml" -u "$(ANSIBLE_USER)" $(ANSIBLE_FLAGS); \
	'

.PHONY: dns.accept
dns.accept: ## DNS acceptance (VIP queries, HA checks, NAT checks, idempotency)
	bash "$(OPS_SCRIPTS_DIR)/dns-accept.sh"

.PHONY: dns.sdn.accept
dns.sdn.accept: ## DNS SDN acceptance (DNS plane validation; read-only)
	@test "$(ENV)" = "samakia-dns" || (echo "ERROR: set ENV=samakia-dns"; exit 2)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) runner.env.check; \
		bash "$(OPS_SCRIPTS_DIR)/dns-sdn-accept.sh"; \
	'

.PHONY: dns.up
dns.up: ## One-command DNS deployment (tf apply -> bootstrap -> dns -> acceptance)
	@bash -euo pipefail -c '\
		if [[ "$(ENV)" != "samakia-dns" ]]; then echo "ERROR: set ENV=samakia-dns" >&2; exit 2; fi; \
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) runner.env.check; \
		$(MAKE) minio.backend.smoke ENV=samakia-minio; \
		ENV=samakia-minio bash "$(OPS_SCRIPTS_DIR)/minio-quorum-guard.sh"; \
		$(MAKE) dns.tf.plan; \
		$(MAKE) dns.tf.apply; \
		# Phase 1 bootstrap for LAN-reachable edges first, then VLAN-only auth via ProxyJump.\n\
		edges_need_bootstrap=0; \
		for ip in 192.168.11.111 192.168.11.112; do \
			if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "root@$$ip" true >/dev/null 2>&1; then edges_need_bootstrap=1; fi; \
		done; \
		if [[ "$$edges_need_bootstrap" -eq 1 ]]; then \
			ANSIBLE_FLAGS="$(ANSIBLE_FLAGS) --limit dns-edge-*" $(MAKE) ansible.bootstrap ENV="$(ENV)"; \
		fi; \
		# Pick a reachable edge as jump host for VLAN-only auth nodes.\n\
		jump=""; \
		for ip in 192.168.11.111 192.168.11.112; do \
			if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "samakia@$$ip" true >/dev/null 2>&1; then jump="samakia@$$ip"; break; fi; \
		done; \
		if [[ -z "$$jump" ]]; then echo "ERROR: cannot reach any DNS edge as samakia (192.168.11.111/112); bootstrap cannot proceed" >&2; exit 1; fi; \
		auth_need_bootstrap=0; \
		for ip in 10.10.100.21 10.10.100.22; do \
			if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new -o ProxyJump="$$jump" "root@$$ip" true >/dev/null 2>&1; then auth_need_bootstrap=1; fi; \
		done; \
		if [[ "$$auth_need_bootstrap" -eq 1 ]]; then \
			ANSIBLE_FLAGS="$(ANSIBLE_FLAGS) --limit dns-auth-1,dns-auth-2" $(MAKE) ansible.bootstrap ENV="$(ENV)"; \
		fi; \
		$(MAKE) dns.ansible.apply; \
		$(MAKE) dns.accept; \
	'

###############################################################################
# Shared control-plane services (Phase 2.1)
###############################################################################

.PHONY: shared.ansible.apply
shared.ansible.apply: ## Shared services Ansible apply (shared.yml orchestrator)
	@test "$(ENV)" = "samakia-shared" || (echo "ERROR: set ENV=samakia-shared"; exit 2)
	@test -d "$(ANSIBLE_DIR)" || (echo "ERROR: ANSIBLE_DIR not found: $(ANSIBLE_DIR)"; exit 1)
	@command -v ansible-playbook >/dev/null 2>&1 || (echo "ERROR: ansible-playbook not found in PATH"; exit 1)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		extra_vars=""; \
		if [[ "${VAULT_FORCE_REINIT:-}" = "1" ]]; then extra_vars="--extra-vars vault_server_force_reinit=true"; fi; \
		FABRIC_TERRAFORM_ENV="$(ENV)" ANSIBLE_CONFIG="$(ANSIBLE_DIR)/ansible.cfg" \
			ansible-playbook -i "$(ANSIBLE_INVENTORY_PATH)" "$(ANSIBLE_DIR)/playbooks/shared.yml" -u "$(ANSIBLE_USER)" $$extra_vars $(ANSIBLE_FLAGS); \
	'

.PHONY: shared.sdn.accept
shared.sdn.accept: ## Shared SDN acceptance (shared plane validation; read-only)
	@test "$(ENV)" = "samakia-shared" || (echo "ERROR: set ENV=samakia-shared"; exit 2)
	@bash -euo pipefail -c '\
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) runner.env.check; \
		bash "$(OPS_SCRIPTS_DIR)/shared-sdn-accept.sh"; \
	'

.PHONY: shared.ntp.accept
shared.ntp.accept: ## Shared NTP acceptance (chrony + VIP)
	@test "$(ENV)" = "samakia-shared" || (echo "ERROR: set ENV=samakia-shared"; exit 2)
	@bash "$(OPS_SCRIPTS_DIR)/shared-ntp-accept.sh"

.PHONY: shared.vault.accept
shared.vault.accept: ## Shared Vault acceptance (VIP + status)
	@test "$(ENV)" = "samakia-shared" || (echo "ERROR: set ENV=samakia-shared"; exit 2)
	@bash "$(OPS_SCRIPTS_DIR)/shared-vault-accept.sh"

.PHONY: shared.pki.accept
shared.pki.accept: ## Shared PKI acceptance (Vault PKI engine)
	@test "$(ENV)" = "samakia-shared" || (echo "ERROR: set ENV=samakia-shared"; exit 2)
	@bash "$(OPS_SCRIPTS_DIR)/shared-pki-accept.sh"

.PHONY: shared.obs.accept
shared.obs.accept: ## Shared observability acceptance (Grafana/Prometheus/Alertmanager/Loki)
	@test "$(ENV)" = "samakia-shared" || (echo "ERROR: set ENV=samakia-shared"; exit 2)
	@bash "$(OPS_SCRIPTS_DIR)/shared-obs-accept.sh"

.PHONY: shared.obs.ingest.accept
shared.obs.ingest.accept: ## Shared observability ingestion acceptance (Loki series)
	@test "$(ENV)" = "samakia-shared" || (echo "ERROR: set ENV=samakia-shared"; exit 2)
	@bash "$(OPS_SCRIPTS_DIR)/shared-obs-ingest-accept.sh"

.PHONY: shared.runtime.invariants.accept
shared.runtime.invariants.accept: ## Shared runtime invariants acceptance (systemd readiness)
	@test "$(ENV)" = "samakia-shared" || (echo "ERROR: set ENV=samakia-shared"; exit 2)
	@bash "$(OPS_SCRIPTS_DIR)/shared-runtime-invariants-accept.sh"

.PHONY: shared.accept
shared.accept: ## Shared services acceptance (SDN + NTP + Vault + PKI + Observability)
	@ENV="$(ENV)" $(MAKE) shared.sdn.accept
	@ENV="$(ENV)" $(MAKE) shared.ntp.accept
	@ENV="$(ENV)" $(MAKE) shared.vault.accept
	@ENV="$(ENV)" $(MAKE) shared.pki.accept
	@ENV="$(ENV)" $(MAKE) shared.obs.accept

.PHONY: shared.up
shared.up: ## One-command shared services deployment (tf apply -> bootstrap -> shared -> acceptance)
	@bash -euo pipefail -c '\
		if [[ "$(ENV)" != "samakia-shared" ]]; then echo "ERROR: set ENV=samakia-shared" >&2; exit 2; fi; \
		env_file="$(RUNNER_ENV_FILE)"; \
		if [[ -f "$$env_file" ]]; then source "$$env_file"; fi; \
		$(MAKE) runner.env.check; \
		if [[ "$(DRY_RUN)" = "1" ]]; then \
			echo "DRY_RUN=1: planning only (no terraform apply, no ansible)"; \
			$(MAKE) tf.plan ENV="$(ENV)" CI=1; \
			exit 0; \
		fi; \
		bash "$(OPS_SCRIPTS_DIR)/proxmox-sdn-ensure-shared-plane.sh" --apply; \
		$(MAKE) tf.plan ENV="$(ENV)"; \
		$(MAKE) tf.apply ENV="$(ENV)" CI=1; \
		bash "$(OPS_SCRIPTS_DIR)/proxmox-lxc-ensure-running.sh" "$(ENV)"; \
		$(MAKE) inventory.check ENV="$(ENV)"; \
		edges_need_bootstrap=0; \
		for ip in 192.168.11.106 192.168.11.107; do \
			if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "root@$$ip" true >/dev/null 2>&1; then edges_need_bootstrap=1; fi; \
		done; \
		if [[ "$$edges_need_bootstrap" -eq 1 ]]; then \
			ANSIBLE_FLAGS="$(ANSIBLE_FLAGS) --limit ntp-*" $(MAKE) ansible.bootstrap ENV="$(ENV)"; \
		fi; \
		jump=""; \
		for ip in 192.168.11.106 192.168.11.107; do \
			if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "samakia@$$ip" true >/dev/null 2>&1; then jump="samakia@$$ip"; break; fi; \
		done; \
		if [[ -z "$$jump" ]]; then echo "ERROR: cannot reach any shared edge as samakia (192.168.11.106/107); bootstrap cannot proceed" >&2; exit 1; fi; \
		vlan_bootstrap_hosts=(); \
		if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new -o ProxyJump="$$jump" "root@10.10.120.21" true >/dev/null 2>&1; then vlan_bootstrap_hosts+=("vault-1"); fi; \
		if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new -o ProxyJump="$$jump" "root@10.10.120.22" true >/dev/null 2>&1; then vlan_bootstrap_hosts+=("vault-2"); fi; \
		if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new -o ProxyJump="$$jump" "root@10.10.120.31" true >/dev/null 2>&1; then vlan_bootstrap_hosts+=("obs-1"); fi; \
		if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new -o ProxyJump="$$jump" "root@10.10.120.32" true >/dev/null 2>&1; then vlan_bootstrap_hosts+=("obs-2"); fi; \
		if [[ "$${#vlan_bootstrap_hosts[@]}" -gt 0 ]]; then \
			vlan_bootstrap_list="$$(IFS=,; echo "$${vlan_bootstrap_hosts[*]}")"; \
			ANSIBLE_FLAGS="$(ANSIBLE_FLAGS) --limit $${vlan_bootstrap_list}" $(MAKE) ansible.bootstrap ENV="$(ENV)"; \
		fi; \
		$(MAKE) shared.ansible.apply ENV="$(ENV)"; \
		$(MAKE) shared.accept ENV="$(ENV)"; \
	'

###############################################################################
# Tenant bindings (Phase 12 Part 1)
###############################################################################

.PHONY: bindings.validate
bindings.validate: ## Validate tenant bindings (schema + semantics + safety)
	@bash "$(REPO_ROOT)/ops/bindings/validate/validate-binding-schema.sh"
	@bash "$(REPO_ROOT)/ops/bindings/validate/validate-binding-semantics.sh"
	@bash "$(REPO_ROOT)/ops/bindings/validate/validate-binding-safety.sh"

.PHONY: bindings.render
bindings.render: ## Render binding connection manifests (read-only)
	@TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" bash "$(REPO_ROOT)/ops/bindings/render/render-connection-manifest.sh"

.PHONY: bindings.apply
bindings.apply: ## Apply binding (guarded; non-prod only by default)
	@TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" BIND_EXECUTE="$(BIND_EXECUTE)" BIND_PROD_APPROVED="$(BIND_PROD_APPROVED)" \
		MAINT_WINDOW_START="$(MAINT_WINDOW_START)" MAINT_WINDOW_END="$(MAINT_WINDOW_END)" \
		EVIDENCE_SIGN="$(EVIDENCE_SIGN)" EVIDENCE_SIGN_KEY="$(EVIDENCE_SIGN_KEY)" \
		bash "$(REPO_ROOT)/ops/bindings/apply/bind.sh"

.PHONY: bindings.secrets.inspect
bindings.secrets.inspect: ## Inspect binding secret refs (presence-only)
	@TENANT="$(TENANT)" BIND_SECRETS_BACKEND="$(BIND_SECRETS_BACKEND)" \
		bash "$(REPO_ROOT)/ops/bindings/secrets/inspect.sh"

.PHONY: bindings.secrets.materialize
bindings.secrets.materialize: ## Materialize binding secrets (guarded; execute with MATERIALIZE_EXECUTE=1)
	@TENANT="$(TENANT)" MATERIALIZE_EXECUTE="$(MATERIALIZE_EXECUTE)" \
		BIND_SECRETS_BACKEND="$(BIND_SECRETS_BACKEND)" BIND_SECRET_INPUT_FILE="$(BIND_SECRET_INPUT_FILE)" \
		SECRETS_GENERATE="$(SECRETS_GENERATE)" SECRETS_GENERATE_ALLOWLIST="$(SECRETS_GENERATE_ALLOWLIST)" \
		VAULT_ENABLE="$(VAULT_ENABLE)" \
		EVIDENCE_SIGN="$(EVIDENCE_SIGN)" EVIDENCE_SIGN_KEY="$(EVIDENCE_SIGN_KEY)" \
		MAINT_WINDOW_START="$(MAINT_WINDOW_START)" MAINT_WINDOW_END="$(MAINT_WINDOW_END)" \
		bash "$(REPO_ROOT)/ops/bindings/secrets/materialize.sh"

.PHONY: bindings.secrets.materialize.dryrun
bindings.secrets.materialize.dryrun: ## Dry-run binding secret materialization
	@TENANT="$(TENANT)" MATERIALIZE_EXECUTE=0 \
		BIND_SECRETS_BACKEND="$(BIND_SECRETS_BACKEND)" BIND_SECRET_INPUT_FILE="$(BIND_SECRET_INPUT_FILE)" \
		SECRETS_GENERATE="$(SECRETS_GENERATE)" SECRETS_GENERATE_ALLOWLIST="$(SECRETS_GENERATE_ALLOWLIST)" \
		VAULT_ENABLE="$(VAULT_ENABLE)" \
		bash "$(REPO_ROOT)/ops/bindings/secrets/materialize.sh"

.PHONY: bindings.secrets.rotate.plan
bindings.secrets.rotate.plan: ## Plan binding secret rotation (read-only)
	@TENANT="$(TENANT)" ROTATION_STAMP="$(ROTATION_STAMP)" \
		bash "$(REPO_ROOT)/ops/bindings/rotate/rotate-plan.sh"

.PHONY: bindings.secrets.rotate.dryrun
bindings.secrets.rotate.dryrun: ## Dry-run binding secret rotation (evidence only)
	@TENANT="$(TENANT)" ROTATION_STAMP="$(ROTATION_STAMP)" \
		bash "$(REPO_ROOT)/ops/bindings/rotate/rotate-dryrun.sh"

.PHONY: bindings.secrets.rotate
bindings.secrets.rotate: ## Rotate binding secrets (guarded; execute with ROTATE_EXECUTE=1)
	@TENANT="$(TENANT)" ROTATE_EXECUTE="$(ROTATE_EXECUTE)" BIND_SECRETS_BACKEND="$(BIND_SECRETS_BACKEND)" \
		ROTATE_INPUT_FILE="$(ROTATE_INPUT_FILE)" BIND_SECRET_INPUT_FILE="$(BIND_SECRET_INPUT_FILE)" \
		SECRETS_GENERATE="$(SECRETS_GENERATE)" SECRETS_GENERATE_ALLOWLIST="$(SECRETS_GENERATE_ALLOWLIST)" \
		EVIDENCE_SIGN="$(EVIDENCE_SIGN)" EVIDENCE_SIGN_KEY="$(EVIDENCE_SIGN_KEY)" \
		MAINT_WINDOW_START="$(MAINT_WINDOW_START)" MAINT_WINDOW_END="$(MAINT_WINDOW_END)" \
		bash "$(REPO_ROOT)/ops/bindings/rotate/rotate.sh"

.PHONY: bindings.verify.offline
bindings.verify.offline: ## Verify bindings (offline; read-only)
	@TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" VERIFY_MODE=offline \
		BIND_SECRETS_BACKEND="$(BIND_SECRETS_BACKEND)" BINDINGS_ARTIFACT_ROOT="$(BINDINGS_ARTIFACT_ROOT)" \
		bash "$(REPO_ROOT)/ops/bindings/verify/verify.sh"

.PHONY: bindings.verify.live
bindings.verify.live: ## Verify bindings (live; guarded)
	@TENANT="$(TENANT)" WORKLOAD="$(WORKLOAD)" VERIFY_MODE=live VERIFY_LIVE="$(VERIFY_LIVE)" \
		BIND_SECRETS_BACKEND="$(BIND_SECRETS_BACKEND)" BINDINGS_ARTIFACT_ROOT="$(BINDINGS_ARTIFACT_ROOT)" \
		bash "$(REPO_ROOT)/ops/bindings/verify/verify.sh"

.PHONY: phase12.part1.entry.check
phase12.part1.entry.check: ## Phase 12 Part 1 entry checklist
	@bash "$(OPS_SCRIPTS_DIR)/phase12-part1-entry-check.sh"

.PHONY: phase12.part1.accept
phase12.part1.accept: ## Phase 12 Part 1 acceptance (bindings only)
	@bash "$(OPS_SCRIPTS_DIR)/phase12-part1-accept.sh"

.PHONY: phase12.part2.entry.check
phase12.part2.entry.check: ## Phase 12 Part 2 entry checklist (binding secrets)
	@bash "$(OPS_SCRIPTS_DIR)/phase12-part2-entry-check.sh"

.PHONY: phase12.part2.accept
phase12.part2.accept: ## Phase 12 Part 2 acceptance (binding secrets)
	@bash "$(OPS_SCRIPTS_DIR)/phase12-part2-accept.sh"

.PHONY: phase12.part3.entry.check
phase12.part3.entry.check: ## Phase 12 Part 3 entry checklist (binding verification)
	@bash "$(OPS_SCRIPTS_DIR)/phase12-part3-entry-check.sh"

.PHONY: phase12.part3.accept
phase12.part3.accept: ## Phase 12 Part 3 acceptance (binding verification)
	@bash "$(OPS_SCRIPTS_DIR)/phase12-part3-accept.sh"

###############################################################################
# Proposals (Phase 12 Part 4)
###############################################################################

.PHONY: proposals.submit
proposals.submit: ## Submit proposal into inbox (guarded by schema)
	@FILE="$(FILE)" bash "$(REPO_ROOT)/ops/proposals/submit.sh"

.PHONY: proposals.validate
proposals.validate: ## Validate proposal schema + policy
	@PROPOSAL_ID="$(PROPOSAL_ID)" FILE="$(FILE)" VALIDATION_OUT="$(VALIDATION_OUT)" \
		bash "$(REPO_ROOT)/ops/proposals/validate.sh"

.PHONY: proposals.review
proposals.review: ## Generate proposal review bundle (diff + impact)
	@PROPOSAL_ID="$(PROPOSAL_ID)" FILE="$(FILE)" \
		bash "$(REPO_ROOT)/ops/proposals/review.sh"

.PHONY: proposals.approve
proposals.approve: ## Approve proposal (guarded; requires OPERATOR_APPROVE=1)
	@PROPOSAL_ID="$(PROPOSAL_ID)" APPROVER_ID="$(APPROVER_ID)" OPERATOR_APPROVE="$(OPERATOR_APPROVE)" \
		APPROVE_REASON="$(APPROVE_REASON)" EVIDENCE_SIGN="$(EVIDENCE_SIGN)" EVIDENCE_SIGN_KEY="$(EVIDENCE_SIGN_KEY)" \
		bash "$(REPO_ROOT)/ops/proposals/approve.sh"

.PHONY: proposals.reject
proposals.reject: ## Reject proposal (guarded; requires OPERATOR_REJECT=1)
	@PROPOSAL_ID="$(PROPOSAL_ID)" APPROVER_ID="$(APPROVER_ID)" OPERATOR_REJECT="$(OPERATOR_REJECT)" \
		REJECT_REASON="$(REJECT_REASON)" \
		bash "$(REPO_ROOT)/ops/proposals/reject.sh"

.PHONY: proposals.apply
proposals.apply: ## Apply proposal (guarded; uses existing apply paths)
	@PROPOSAL_ID="$(PROPOSAL_ID)" PROPOSAL_APPLY="$(PROPOSAL_APPLY)" APPLY_DRYRUN="$(APPLY_DRYRUN)" \
		BIND_EXECUTE="$(BIND_EXECUTE)" \
		bash "$(REPO_ROOT)/ops/proposals/apply.sh"

###############################################################################
# Self-Service Proposals (Phase 15 Part 1)
###############################################################################

.PHONY: selfservice.submit
selfservice.submit: ## Submit self-service proposal into inbox (read-only)
	@FILE="$(FILE)" bash "$(REPO_ROOT)/ops/selfservice/submit.sh"

.PHONY: selfservice.validate
selfservice.validate: ## Validate self-service proposal schema + policy
	@PROPOSAL_ID="$(PROPOSAL_ID)" FILE="$(FILE)" VALIDATION_OUT="$(VALIDATION_OUT)" \
		bash "$(REPO_ROOT)/ops/selfservice/validate.sh"

.PHONY: selfservice.plan
selfservice.plan: ## Self-service read-only plan and preview
	@PROPOSAL_ID="$(PROPOSAL_ID)" FILE="$(FILE)" \
		bash "$(REPO_ROOT)/ops/selfservice/plan.sh"

.PHONY: selfservice.review
selfservice.review: ## Self-service review bundle (diff + impact + plan)
	@PROPOSAL_ID="$(PROPOSAL_ID)" FILE="$(FILE)" \
		bash "$(REPO_ROOT)/ops/selfservice/review.sh"

.PHONY: phase15.part1.entry.check
phase15.part1.entry.check: ## Phase 15 Part 1 entry checklist (self-service proposals)
	@bash "$(OPS_SCRIPTS_DIR)/phase15-part1-entry-check.sh"

.PHONY: phase15.part1.accept
phase15.part1.accept: ## Phase 15 Part 1 acceptance (self-service proposals)
	@bash "$(OPS_SCRIPTS_DIR)/phase15-part1-accept.sh"

.PHONY: phase12.part4.entry.check
phase12.part4.entry.check: ## Phase 12 Part 4 entry checklist (proposal flow)
	@bash "$(OPS_SCRIPTS_DIR)/phase12-part4-entry-check.sh"

.PHONY: phase12.part4.accept
phase12.part4.accept: ## Phase 12 Part 4 acceptance (proposal flow)
	@bash "$(OPS_SCRIPTS_DIR)/phase12-part4-accept.sh"

###############################################################################
# Drift Awareness (Phase 12 Part 5)
###############################################################################

.PHONY: phase12.part5.entry.check
phase12.part5.entry.check: ## Phase 12 Part 5 entry checklist (drift awareness)
	@bash "$(OPS_SCRIPTS_DIR)/phase12-part5-entry-check.sh"

.PHONY: phase12.part5.accept
phase12.part5.accept: ## Phase 12 Part 5 acceptance (drift awareness)
	@bash "$(OPS_SCRIPTS_DIR)/phase12-part5-accept.sh"

###############################################################################
# Phase 12 Part 6 (Release Readiness Closure)
###############################################################################

.PHONY: phase12.readiness.packet
phase12.readiness.packet: ## Generate Phase 12 release readiness packet (read-only) (TENANT=<id|all>)
	@TENANT="$(TENANT)" ENV="$(ENV)" READINESS_SIGN="$(READINESS_SIGN)" READINESS_STAMP="$(READINESS_STAMP)" \
		PHASE12_PACKET_ROOT="$(PHASE12_PACKET_ROOT)" \
		bash "$(REPO_ROOT)/ops/release/phase12/phase12-readiness-packet.sh"

.PHONY: phase12.part6.entry.check
phase12.part6.entry.check: ## Phase 12 Part 6 entry checklist (release readiness closure)
	@bash "$(OPS_SCRIPTS_DIR)/phase12-part6-entry-check.sh"

.PHONY: phase12.part6.accept
phase12.part6.accept: ## Phase 12 Part 6 acceptance (release readiness closure)
	@bash "$(OPS_SCRIPTS_DIR)/phase12-part6-accept.sh"

.PHONY: phase12.accept
phase12.accept: ## Run Phase 12 acceptance suite (read-only)
	@TENANT="$(TENANT)" ENV="$(ENV)" READINESS_SIGN="$(READINESS_SIGN)" READINESS_STAMP="$(READINESS_STAMP)" \
		PHASE12_PACKET_ROOT="$(PHASE12_PACKET_ROOT)" \
		bash "$(REPO_ROOT)/ops/release/phase12/phase12-readiness-packet.sh"

###############################################################################
# Phase 13 Part 1 (Exposure Plan)
###############################################################################

.PHONY: phase13.part1.entry.check
phase13.part1.entry.check: ## Phase 13 Part 1 entry checklist (exposure plan)
	@bash "$(OPS_SCRIPTS_DIR)/phase13-part1-entry-check.sh"

.PHONY: phase13.part1.accept
phase13.part1.accept: ## Phase 13 Part 1 acceptance (exposure plan)
	@bash "$(OPS_SCRIPTS_DIR)/phase13-part1-accept.sh"

###############################################################################
# Phase 13 Part 2 (Exposure Apply/Verify/Rollback)
###############################################################################

.PHONY: phase13.part2.entry.check
phase13.part2.entry.check: ## Phase 13 Part 2 entry checklist (exposure execute guards)
	@bash "$(OPS_SCRIPTS_DIR)/phase13-part2-entry-check.sh"

.PHONY: phase13.part2.accept
phase13.part2.accept: ## Phase 13 Part 2 acceptance (guarded apply/verify/rollback)
	@bash "$(OPS_SCRIPTS_DIR)/phase13-part2-accept.sh"

.PHONY: phase13.accept
phase13.accept: ## Phase 13 acceptance (umbrella)
	@bash "$(OPS_SCRIPTS_DIR)/phase13-part2-accept.sh"

###############################################################################
# Milestone Phase 1–12 (End-to-End Verification)
###############################################################################

.PHONY: milestone.phase1-12.verify
milestone.phase1-12.verify: ## Verify end-to-end regression for Phase 1–12 (read-only)
	@bash "$(REPO_ROOT)/ops/milestones/phase1-12/verify.sh"

.PHONY: milestone.phase1-12.lock
milestone.phase1-12.lock: ## Lock Phase 1–12 milestone after verify passes
	@bash "$(REPO_ROOT)/ops/milestones/phase1-12/lock.sh"

###############################################################################
# Operator UX (Phase 9)
###############################################################################

.PHONY: docs.operator.check
docs.operator.check: ## Operator docs anti-drift check (cookbook + targets)
	@bash "$(REPO_ROOT)/ops/docs/docs-antidrift-check.sh"

.PHONY: docs.cookbook.lint
docs.cookbook.lint: ## Operator cookbook lint (structure + targets)
	@bash "$(REPO_ROOT)/ops/docs/cookbook-lint.sh"

.PHONY: phase9.entry.check
phase9.entry.check: ## Phase 9 entry checklist (docs/governance only)
	@bash "$(OPS_SCRIPTS_DIR)/phase9-entry-check.sh"

.PHONY: phase9.accept
phase9.accept: ## Phase 9 acceptance (docs/governance only)
	@bash "$(OPS_SCRIPTS_DIR)/phase9-accept.sh"

###############################################################################
# END
###############################################################################
