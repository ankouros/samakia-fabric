# Changelog — Samakia Fabric

All notable changes to this project will be documented in this file.

This project follows:
- Semantic Versioning (SemVer)
- Infrastructure-first change tracking

The format is inspired by:
- Keep a Changelog
- Real-world infrastructure operations

---

## [Unreleased]

### Added
#### Golden image automation
- Artifact-driven golden image auto-bump (no repo edits per version)
  - Version resolver: `ops/scripts/image-next-version.sh` (+ unit test `ops/scripts/test-image-next-version.sh`)
  - `make image.build` now builds next version by default; `VERSION=N` builds an explicit version without overwriting
  - `make image.build-next` prints max/next/artifact path and injects vars into Packer at runtime
  - `fabric-ci/scripts/validate.sh` runs the versioning unit test (no packer, no Proxmox)
- MinIO HA Terraform backend (Terraform + Ansible + acceptance, non-interactive)
  - Terraform env: `fabric-core/terraform/envs/samakia-minio/` (5 LXCs: `minio-edge-1/2`, `minio-1/2/3` with static IPs and pinned image version)
  - Proxmox SDN ensure script: `ops/scripts/proxmox-sdn-ensure-stateful-plane.sh` (zone `zminio`, vnet `vminio`, VLAN140 subnet `10.10.140.0/24`)
  - Ansible playbooks: `fabric-core/ansible/playbooks/state-backend.yml`, `fabric-core/ansible/playbooks/minio.yml`, `fabric-core/ansible/playbooks/minio-edge.yml`
  - Ansible roles: `fabric-core/ansible/roles/minio_cluster`, `fabric-core/ansible/roles/minio_edge_lb`
  - Runner bootstrap helper: `ops/scripts/backend-configure.sh` (local-only credentials + backend CA + HAProxy TLS pem; installs backend CA into host trust store with non-interactive sudo)
  - One-command automation: `make minio.up ENV=samakia-minio` + acceptance `make minio.accept` (`ops/scripts/minio-accept.sh`)
- DNS infrastructure substrate (Terraform + Ansible + acceptance, non-interactive)
  - Terraform env: `fabric-core/terraform/envs/samakia-dns/` (4 LXCs: `dns-edge-1/2`, `dns-auth-1/2` with static IPs and pinned image version)
  - Proxmox SDN ensure script: `ops/scripts/proxmox-sdn-ensure-dns-plane.sh` (zone `zonedns`, vnet `vlandns`, VLAN100 subnet `10.10.100.0/24`)
  - Ansible playbooks: `fabric-core/ansible/playbooks/dns.yml`, `fabric-core/ansible/playbooks/dns-edge.yml`, `fabric-core/ansible/playbooks/dns-auth.yml`
  - Ansible roles: `fabric-core/ansible/roles/dns_edge_gateway`, `fabric-core/ansible/roles/dns_auth_powerdns`
  - One-command automation: `make dns.up` + acceptance `make dns.accept` (`ops/scripts/dns-accept.sh`)
- Phase 1 operational hardening (remote state + runner bootstrapping + CI-safe orchestration)
- Remote Terraform backend initialization for MinIO/S3 with lockfiles (`ops/scripts/tf-backend-init.sh`; no DynamoDB; strict TLS)
- Runner host env management (`ops/scripts/runner-env-install.sh`, `ops/scripts/runner-env-check.sh`) with canonical env file `~/.config/samakia-fabric/env.sh` (chmod 600; presence-only output)
- Optional backend CA installer for MinIO/S3 (`ops/scripts/install-s3-backend-ca.sh`) to support strict TLS without insecure flags
- Environment parity guardrail (`ops/scripts/env-parity-check.sh`) enforcing dev/staging/prod structural equivalence
- New Terraform environment `fabric-core/terraform/envs/samakia-staging/` (parity with dev/prod)
- Inventory sanity guardrail for DHCP/IP determinism (`ops/scripts/inventory-sanity-check.sh`) + `make inventory.check`
- SSH trust lifecycle tools (`ops/scripts/ssh-trust-rotate.sh`, `ops/scripts/ssh-trust-verify.sh`) to support strict host key checking after replace/recreate
- Phase 1 acceptance suite (`ops/scripts/phase1-accept.sh` + `make phase1.accept`) to validate parity, runner env, inventory parse, and non-interactive Terraform plan
- `OPERATIONS_LXC_LIFECYCLE.md` (replace-in-place vs blue/green runbook; DHCP/MAC determinism and SSH trust workflow)
- Future improvements tracked in `ROADMAP.md`
- `INCIDENT_SEVERITY_TAXONOMY.md` (S0–S4) with evidence depth + signing/dual-control/TSA requirements
- `OPERATIONS_POST_INCIDENT_FORENSICS.md` severity-driven evidence collection flow (proportional, authorization-first)
- `ops/scripts/forensics-severity-guide.sh` (read-only helper that prints evidence/signing requirements by severity)
- `LEGAL_HOLD_RETENTION_POLICY.md` and `OPERATIONS_LEGAL_HOLD_RETENTION.md` (legal hold + retention governance for evidence artifacts)
- `ops/scripts/legal-hold-manage.sh` (labels-only helper for declaring/listing/validating legal holds; no deletion)
- `OPERATIONS_CROSS_INCIDENT_CORRELATION.md` (cross-incident correlation playbook: canonical timelines + hypothesis register, derived artifacts only)
- `ops/scripts/correlation-timeline-builder.sh` (read-only helper that builds deterministic first-draft timelines from existing evidence manifests)
- `SECURITY_THREAT_MODELING.md` (explicit threat modeling approach + platform decomposition + threat catalog mapped to controls and S0–S4 severity)
- `ops/scripts/threat-model-index.sh` (read-only helper to index threats by severity/component/STRIDE)
- `OPERATIONS_HA_FAILURE_SIMULATION.md` (GameDays runbook: HA failure scenarios with safety gates, abort criteria, verification and rollback steps)
- `ops/scripts/ha-precheck.sh` and `ops/scripts/ha-sim-verify.sh` (read-only helpers for HA GameDays; no automated shutdowns or network tampering)
- `OPERATIONS_PRE_RELEASE_READINESS.md` (pre-release readiness audit runbook: checklist-driven Go/No-Go, signable readiness packet definition)
- `ops/scripts/pre-release-readiness.sh` (optional helper to scaffold `release-readiness/<release-id>/` with evidence references; no enforcement, no signing, no network)

### Changed
- Migrated Codex remediation log into `CHANGELOG.md` (retired `codex-changelog.md`)
- Enforced Proxmox API token-only auth in Terraform envs and runner guardrails (password auth variables are no longer supported)
- Enabled strict SSH host key checking in Ansible (`fabric-core/ansible/ansible.cfg`), requiring explicit known_hosts rotation/enrollment on host replacement
- MinIO HA backend corrections (repo-wide): SDN zone/vnet renamed to `zminio`/`vminio` (≤ 8 chars) and MinIO LAN VIP set to `192.168.11.101` (updated Terraform/Ansible/scripts/docs; `dns-edge-1` LAN IP moved to `192.168.11.103` to avoid VIP collision)

### Fixed
- Excluded `<evidence>/legal-hold/` label packs from evidence `manifest.sha256` generation while keeping label packs independently signable/notarizable
- Ensured `ops/scripts/compliance-snapshot.sh` exports signer public keys in sign-only mode so verification works offline for add-on packs (e.g., legal hold records)

### Removed
- —

---

## [1.0.0] — 2025-12-27

### Added
#### Core Architecture
- Proxmox VE–centric infrastructure design
- LXC-first compute model
- Rebuild-over-repair operational philosophy
- Delegated Proxmox user model for automation

#### Packer
- Golden image pipeline for Ubuntu 24.04 LTS (LXC)
- Docker-based rootfs build
- Image hygiene:
  - machine-id reset
  - SSH host key cleanup
  - password authentication disabled
- Versioned LXC templates (`v1`, `v2`)

#### Terraform
- Proxmox LXC Terraform modules
- Explicit Proxmox 9 guards:
  - Immutable LXC feature flags
  - Lifecycle ignore rules
  - No implicit `local` storage usage
- Environment separation (`envs/dev`, `envs/prod`)
- Deterministic VMID handling
- SSH key injection via Terraform

#### Ansible
- Terraform-driven dynamic inventory
- Bootstrap model for LXC containers
- Separation of bootstrap vs day-2 configuration
- Non-root operator access model
- SSH hardening via configuration, not images

#### Security
- SSH key-only access model
- Root SSH access limited to bootstrap
- No users or secrets baked into images
- Least-privilege automation enforced

---

### Documentation
- `README.md` — public project overview
- `ARCHITECTURE.md` — system design & boundaries
- `DECISIONS.md` — Architecture Decision Records (ADR)
- `OPERATIONS.md` — operational runbooks
- `SECURITY.md` — security policy & threat model
- `STYLEGUIDE.md` — IaC and ops conventions
- `ROADMAP.md` — phased project evolution
- `docs/glossary.md` — canonical terminology
- `CONTRIBUTING.md` — contribution rules
- `AGENTS.md` — AI agent operating constraints
- `CODE_OF_CONDUCT.md` — contributor behavior
- `LICENSE` — Apache 2.0

---

### Fixed
- Proxmox 9 compatibility issues with Terraform provider
- LXC template import edge cases
- SSH access issues caused by image misconfiguration
- Rootfs export format inconsistencies

---

### Removed
- Implicit defaults (storage, bridge, users)
- Password-based SSH access
- Root@pam usage in automation
- In-image provisioning logic

---

## Versioning Notes

- **MAJOR** versions may introduce breaking architectural changes
- **MINOR** versions add backward-compatible functionality
- **PATCH** versions fix bugs without behavior changes
- Golden images are versioned independently from the framework

---

## Change Governance

All changes must:
- Be tracked in this file
- Be traceable to commits
- Respect existing ADRs
- Update documentation where applicable

Untracked changes are considered defects.

---

## Final Note

Samakia Fabric values **predictability over velocity**.

If a change is not documented here,
it is assumed to not exist.

---

## Codex Remediation Log (migrated)

This section was migrated from `codex-changelog.md`. Future entries must be recorded in `CHANGELOG.md`.

### Executive Summary

Aligned the bootstrap contract across Packer, Terraform, and Ansible, removed committed secrets, enforced strict TLS handling with host-trusted Proxmox CA, tightened Terraform provider rules, reduced build nondeterminism, and replaced placeholder CI scripts with real validation steps. Added a token-based Proxmox API upload path for LXC templates, ensured images include a minimal Ansible runtime (Python), and made Ansible inventory resilient to DHCP changes by resolving container IPs via the Proxmox API when credentials are provided.

### Changes

1. **Aligned golden image bootstrap contract (userless images + temporary root SSH)**
   - Files affected: `fabric-core/packer/lxc/ubuntu-24.04/provision.sh`, `fabric-core/packer/lxc/ubuntu-24.04/packer.pkr.hcl`
   - Reason: Packer created a user and disabled root SSH, conflicting with Terraform key injection and Ansible bootstrap flow.
   - Risk level: high
   - Behavior change: Images are now userless; root SSH is key-only for bootstrap; Packer no longer creates users or sudoers entries; gzip output is deterministic.

2. **Stopped Terraform from managing LXC feature flags**
   - Files affected: `fabric-core/terraform/modules/lxc-container/main.tf`, `fabric-core/terraform/modules/lxc-container/README.md`
   - Reason: Delegated-user constraint prohibits feature flag management, and docs explicitly forbid it.
   - Risk level: medium
   - Behavior change: Terraform no longer sets `keyctl`/`nesting`; feature flags remain host-level and immutable.

3. **Removed hardcoded SSH keys and enforced variable-based injection**
   - Files affected: `fabric-core/terraform/envs/samakia-prod/main.tf`
   - Reason: Hardcoded keys violate GitOps and prevent key rotation.
   - Risk level: low
   - Behavior change: SSH keys are now provided via `var.ssh_public_keys` only.

4. **Made TLS handling explicit and secure by default**
   - Files affected: `fabric-core/terraform/envs/samakia-prod/variables.tf`, `fabric-core/terraform/envs/samakia-prod/provider.tf`, `docs/tutorials/03-deploy-lxc-with-terraform.md`
   - Reason: `pm_tls_insecure` must not default to insecure behavior.
   - Risk level: medium
   - Behavior change: TLS is secure by default; insecure mode requires explicit opt-in.

5. **Removed committed secrets and converted tfvars to an example**
   - Files affected: `fabric-core/terraform/envs/samakia-prod/terraform.tfvars`, `fabric-core/terraform/envs/samakia-prod/terraform.tfvars.example`, `docs/tutorials/03-deploy-lxc-with-terraform.md`
   - Reason: Passwords must never be committed to VCS.
   - Risk level: low
   - Behavior change: `terraform.tfvars` is no longer tracked; an example file with placeholders is provided and docs reference the example.

6. **Implemented real bootstrap logic in Ansible**
   - Files affected: `fabric-core/ansible/playbooks/bootstrap.yml`
   - Reason: Bootstrap playbook was a no-op, leaving the system unusable and inconsistent with docs.
   - Risk level: high
   - Behavior change: Bootstrap now creates a non-root user, installs authorized keys, configures sudo, and disables root SSH.

7. **Improved inventory generation to avoid manual output files**
   - Files affected: `fabric-core/ansible/inventory/terraform.py`
   - Reason: Inventory required a manual `terraform-output.json` step.
   - Risk level: low
   - Behavior change: Inventory now attempts `terraform output -json` if the file is missing.

8. **Replaced placeholder CI scripts with enforceable checks**
   - Files affected: `fabric-ci/scripts/enforce-terraform-provider.sh`, `fabric-ci/scripts/lint.sh`, `fabric-ci/scripts/validate.sh`, `fabric-ci/scripts/smoke-test.sh`, `fabric-ci/README.md`
   - Reason: Hooks were non-functional and did not enforce project rules.
   - Risk level: medium
   - Behavior change: CI scripts now enforce provider pinning, Terraform fmt/validate, and Ansible syntax checks.

9. **Updated operational and tutorial documentation to match behavior**
   - Files affected: `docs/tutorials/01-bootstrap-proxmox.md`, `docs/tutorials/02-build-lxc-image.md`, `docs/tutorials/03-deploy-lxc-with-terraform.md`, `docs/tutorials/04-bootstrap-with-ansible.md`, `OPERATIONS.md`
   - Reason: Documentation described a userless image and root bootstrap model, but code did not follow it.
   - Risk level: low
   - Behavior change: Documentation now reflects the enforced bootstrap contract and TLS defaults.

10. **Normalized Terraform provider source casing**
   - Files affected: `fabric-core/terraform/modules/lxc-container/versions.tf`, `fabric-core/terraform/envs/samakia-prod/versions.tf`, `fabric-core/terraform/envs/samakia-dev/versions.tf`
   - Reason: Mixed casing can cause provider resolution inconsistencies.
   - Risk level: low
   - Behavior change: Provider source is consistently `telmate/proxmox`.

11. **Added API token auth support for Terraform env**
   - Files affected: `fabric-core/terraform/envs/samakia-prod/variables.tf`, `fabric-core/terraform/envs/samakia-prod/provider.tf`, `fabric-core/terraform/envs/samakia-prod/checks.tf`
   - Reason: Token auth is the preferred production pattern; environment must support it safely and reject mixed auth configuration.
   - Risk level: medium
   - Behavior change: Environment accepts token credentials (`pm_api_token_id`, `pm_api_token_secret`) and rejects mixed token+password configuration at plan/apply time.

12. **Prevented feature-flag drift from producing Terraform changes**
   - Files affected: `fabric-core/terraform/modules/lxc-container/main.tf`
   - Reason: Feature flags are immutable host-level controls and must not be changed by Terraform; removing the block created a plan drift on existing containers.
   - Risk level: low
   - Behavior change: Terraform ignores feature drift so existing containers do not plan in-place updates.

13. **Allowed required audit outputs in Git ignore rules**
   - Files affected: `.gitignore`
   - Reason: `CHANGELOG.md` and `REVIEW.md` were ignored by default, preventing required documentation from being tracked.
   - Risk level: low
   - Behavior change: These two files are now explicitly allowed while other Codex artifacts remain ignored.

14. **Applied the same Proxmox auth pattern to `samakia-dev`**
   - Files affected: `fabric-core/terraform/envs/samakia-dev/provider.tf`, `fabric-core/terraform/envs/samakia-dev/variables.tf`, `fabric-core/terraform/envs/samakia-dev/checks.tf`, `fabric-core/terraform/envs/samakia-dev/terraform.tfvars.example`
   - Reason: Dev and prod must follow the same security and correctness contract (token-first, explicit TLS, and checks).
   - Risk level: low
   - Behavior change: Dev environment now supports token auth, rejects mixed auth configs, and has a safe example tfvars file.

15. **Made CI scripts runnable and fixed validation execution context**
   - Files affected: `fabric-ci/scripts/lint.sh`, `fabric-ci/scripts/validate.sh`, `fabric-ci/scripts/smoke-test.sh`
   - Reason: Scripts were present but not reliably runnable or environment-aware.
   - Risk level: low
   - Behavior change: Scripts now run end-to-end as expected and use the repo Ansible config explicitly (`ANSIBLE_CONFIG`).

16. **Fixed Ansible config deprecation to keep CI “clean”**
   - Files affected: `fabric-core/ansible/ansible.cfg`
   - Reason: `collections_paths` is deprecated; warnings in validation reduce signal and will become failures over time.
   - Risk level: low
   - Behavior change: Validation output no longer emits the `collections_paths` deprecation warning.

17. **Updated tfvars example to prefer API tokens**
   - Files affected: `fabric-core/terraform/envs/samakia-prod/terraform.tfvars.example`
   - Reason: Token auth is the preferred automation model; examples must match the intended secure default.
   - Risk level: low
   - Behavior change: The prod example is token-first and documents password auth as fallback only.

18. **Fixed Ansible bootstrap playbook defaults and lint compliance**
   - Files affected: `fabric-core/ansible/playbooks/bootstrap.yml`
   - Reason: `ansible-playbook playbooks/bootstrap.yml` must be runnable with safe defaults and pass ansible-lint/pre-commit; prior changes introduced a recursion bug and lint issues.
   - Risk level: medium
   - Behavior change: Bootstrap uses `remote_user: root` explicitly and defaults `bootstrap_authorized_keys` from the controller’s `~/.ssh` keys when not provided.

19. **Made dynamic inventory self-contained for connection variables**
   - Files affected: `fabric-core/ansible/inventory/terraform.py`, `fabric-core/ansible/host_vars/monitoring-1.yml`
   - Reason: Ansible playbook execution ignored `host_vars` for connection-time vars in this setup; inventory needed to include connection vars explicitly to make bootstrap runnable without manual steps.
   - Risk level: low
   - Behavior change: Inventory now merges simple `host_vars/<hostname>.yml` key/value pairs into `_meta.hostvars`, including `ansible_host`.

20. **Renamed Proxmox CA role to satisfy ansible-lint role naming contract**
   - Files affected: `fabric-core/ansible/roles/proxmox_ca/README.md`, `fabric-core/ansible/roles/proxmox_ca/defaults/main.yml`, `fabric-core/ansible/roles/proxmox_ca/tasks/main.yml`, `fabric-core/ansible/roles/proxmox_ca/handlers/main.yml`, `fabric-core/ansible/roles/proxmox_ca/files/proxmox-root-ca.crt`, `fabric-core/ansible/playbooks/bootstrap.yml`
   - Reason: `proxmox-ca` violated ansible-lint `role-name` rules; handler naming and idempotency rules were also failing pre-commit.
   - Risk level: low
   - Behavior change: Role name is now `proxmox_ca`, handler names are properly cased, and `update-ca-certificates` has an explicit `changed_when`.

21. **Brought bootstrap role tasks up to ansible-lint standards**
   - Files affected: `fabric-core/ansible/roles/bootstrap/tasks/main.yml`
   - Reason: Role tasks were missing YAML document start and FQCN module usage, causing ansible-lint risk.
   - Risk level: low
   - Behavior change: Uses `ansible.builtin.user` and `ansible.posix.authorized_key` with a valid YAML header.

22. **Re-enabled Terraform enforcement of `ssh_public_keys` drift**
   - Files affected: `fabric-core/terraform/modules/lxc-container/main.tf`
   - Reason: Bootstrap access depends on SSH key injection being enforceable; ignoring `ssh_public_keys` prevents safe recovery/rotation and can lead to lockout.
   - Risk level: medium
   - Behavior change: Terraform no longer ignores changes to `ssh_public_keys` while continuing to ignore Proxmox-normalized attributes (`network`, `tags`, `features`).

23. **Added Proxmox API token-based upload for LXC templates (no SSH/root on node)**
   - Files affected: `fabric-core/packer/lxc/scripts/upload-lxc-template-via-api.sh`, `docs/tutorials/02-build-lxc-image.md`
   - Reason: The prior import workflow depended on `root@<node>` SSH, which conflicts with delegated-user and GitOps automation constraints; template delivery must work with API tokens.
   - Risk level: low
   - Behavior change: LXC rootfs artifacts can be uploaded to `storage:vztmpl/...` via Proxmox API using `PM_*`/`TF_VAR_*` environment variables; secrets are not stored in repo.

24. **Version-bumped golden image to include an Ansible runtime baseline**
   - Files affected: `fabric-core/packer/lxc/ubuntu-24.04/packer.pkr.hcl`, `fabric-core/packer/lxc/ubuntu-24.04/provision.sh`, `docs/tutorials/02-build-lxc-image.md`
   - Reason: Bootstrap failed because the container lacked Python, which is required for Ansible modules (and `python3-apt` for apt-based tasks).
   - Risk level: medium
   - Behavior change: Default image version is now `v3` (`ubuntu-24.04-lxc-rootfs-v3.tar.gz`) and includes `python3` + `python3-apt` while remaining userless and key-only.

25. **Updated prod Terraform environment to consume the new `v3` template**
   - Files affected: `fabric-core/terraform/envs/samakia-prod/main.tf`, `docs/tutorials/03-deploy-lxc-with-terraform.md`
   - Reason: The running container needed to be recreated from the corrected immutable image to satisfy the bootstrap contract end-to-end.
   - Risk level: high
   - Behavior change: Template change forces destroy/recreate of the LXC container (intended immutability behavior).

26. **Added optional NIC MAC pinning to reduce DHCP churn**
   - Files affected: `fabric-core/terraform/modules/lxc-container/main.tf`, `fabric-core/terraform/modules/lxc-container/variables.tf`, `fabric-core/terraform/modules/lxc-container/README.md`, `fabric-core/terraform/envs/samakia-prod/main.tf`
   - Reason: DHCP-assigned IPs changed on replacement, breaking Ansible connectivity; pinning the MAC is the smallest deterministic lever without introducing IPAM.
   - Risk level: low
   - Behavior change: Module supports an optional `mac_address` input for `eth0`; prod pins it to stabilize leases where the DHCP server honors MAC affinity/reservations.

27. **Made Ansible inventory resilient to DHCP changes via Proxmox API IP discovery**
   - Files affected: `fabric-core/ansible/inventory/terraform.py`, `fabric-core/ansible/host_vars/monitoring-1.yml`
   - Reason: After immutable replacement, the container IP may change; inventory must resolve connectivity without manual IP edits or generated JSON files.
   - Risk level: medium
   - Behavior change: If `ansible_host` is not set in `host_vars`, inventory queries `GET /nodes/<node>/lxc/<vmid>/interfaces` using `TF_VAR_pm_api_*`/`PM_*` env vars and injects the discovered IPv4 as `ansible_host`.

28. **Fixed bootstrap key resolution and made the playbook role-compatible**
   - Files affected: `fabric-core/ansible/playbooks/bootstrap.yml`
   - Reason: The previous “auto-detect controller keys” logic had a recursion bug and did not populate `bootstrap_authorized_keys` for roles, causing runtime failures.
   - Risk level: medium
   - Behavior change: Bootstrap keys are resolved once via `set_fact`, safely defaulting from `~/.ssh` when available, and then published for both the playbook tasks and the `bootstrap` role; re-runs are idempotent.

29. **Finalized host-based Proxmox CA trust model (no insecure TLS flags)**
   - Files affected: `ops/ca/proxmox-root-ca.crt`, `ops/scripts/install-proxmox-ca.sh`, `fabric-ci/scripts/check-proxmox-ca-and-tls.sh`, `fabric-ci/scripts/validate.sh`
   - Reason: Terraform and Ansible runners must trust Proxmox API TLS via the host OS trust store; insecure TLS bypasses are forbidden.
   - Risk level: medium
   - Behavior change: When Proxmox API variables are set, validation now fails if the CA file is missing, not installed into the host trust store, or not a real CA certificate (`CA:TRUE`).

30. **Removed insecure TLS configuration from Terraform and upload tooling**
   - Files affected: `fabric-core/terraform/envs/samakia-prod/provider.tf`, `fabric-core/terraform/envs/samakia-prod/variables.tf`, `fabric-core/terraform/envs/samakia-prod/terraform.tfvars.example`, `fabric-core/terraform/envs/samakia-dev/provider.tf`, `fabric-core/terraform/envs/samakia-dev/variables.tf`, `fabric-core/terraform/envs/samakia-dev/terraform.tfvars.example`, `fabric-core/packer/lxc/scripts/upload-lxc-template-via-api.sh`
   - Reason: `pm_tls_insecure` / `curl -k` patterns violate the security contract and encourage silent downgrade of TLS verification.
   - Risk level: medium
   - Behavior change: There is no supported insecure TLS path; CA trust must be installed on the runner host.

31. **Enforced 2-phase Ansible execution model (bootstrap vs harden)**
   - Files affected: `fabric-core/ansible/playbooks/bootstrap.yml`, `fabric-core/ansible/playbooks/harden.yml`, `fabric-core/ansible/roles/bootstrap/tasks/main.yml`, `fabric-ci/scripts/validate.sh`
   - Reason: Bootstrap must be root-only and minimal; non-critical hardening belongs to a separate phase running as the operator user.
   - Risk level: low
   - Behavior change: `bootstrap.yml` no longer includes non-bootstrap roles and now waits for SSH; `harden.yml` exists as a post-bootstrap scaffold and runs as `samakia`.

32. **Made inventory IP resolution strict, TLS-safe, and deterministic-first**
   - Files affected: `fabric-core/ansible/inventory/terraform.py`
   - Reason: Inventory must not rely on DNS and must fail loudly if no IP can be resolved; Proxmox API fallback must use strict TLS and bounded retries.
   - Risk level: medium
   - Behavior change: Inventory now resolves `ansible_host` using priority `host_vars.ansible_host` → Proxmox API IPv4 discovery (strict TLS, retries) → hard failure with actionable error messages; it never logs tokens/secrets.

33. **Single canonical Proxmox CA source for both host and LXC**
   - Files affected: `fabric-core/ansible/roles/proxmox_ca/defaults/main.yml`, `fabric-core/ansible/roles/proxmox_ca/tasks/main.yml`, `ops/ca/proxmox-root-ca.crt`
   - Reason: The Proxmox CA must live at one canonical path for GitOps and auditability; roles must not carry diverging copies.
   - Risk level: low
   - Behavior change: The `proxmox_ca` role now copies the CA from `ops/ca/proxmox-root-ca.crt` instead of a role-local file.

34. **Hardened CI provider-pin enforcement to ignore Terraform plugin binaries**
   - Files affected: `fabric-ci/scripts/enforce-terraform-provider.sh`
   - Reason: Scanning `.terraform/` binaries caused false-positive matches and broke pre-commit.
   - Risk level: low
   - Behavior change: Provider enforcement ignores `.terraform/` and binary files while still enforcing real HCL source constraints.

35. **Removed insecure TLS guidance from operational docs**
   - Files affected: `OPERATIONS.md`, `docs/tutorials/01-bootstrap-proxmox.md`, `docs/tutorials/03-deploy-lxc-with-terraform.md`, `fabric-core/ansible/roles/proxmox_ca/README.md`, `REVIEW.md`
   - Reason: Documentation must not instruct insecure TLS bypasses; it must reflect the strict CA trust model.
   - Risk level: low
   - Behavior change: Documentation now aligns with “install internal CA in runner trust store” and forbids insecure flags.

36. **Implemented production-grade `harden.yml` baseline (phase 2, runs as `samakia`)**
   - Files affected: `fabric-core/ansible/playbooks/harden.yml`, `fabric-core/ansible/roles/hardening_baseline/defaults/main.yml`, `fabric-core/ansible/roles/hardening_baseline/tasks/main.yml`, `fabric-core/ansible/roles/hardening_baseline/handlers/main.yml`
   - Reason: `harden.yml` was a scaffold; production requires a deterministic, LXC-safe post-bootstrap hardening phase that is safe to re-run.
   - Risk level: medium
   - Behavior change: Adds a real hardening phase with SSH daemon hardening (explicit `AllowUsers samakia`, strict auth settings, modern crypto, validated reload), unattended security updates via `unattended-upgrades` (no auto-reboot by default), time sync + timezone sanity, journald persistence/retention defaults, and LXC-safe sysctl hardening applied only when writable.

37. **Made hardening validation GitOps-friendly (lint discoverability)**
   - Files affected: `.ansible/roles/hardening_baseline`
   - Reason: Pre-commit/ansible-lint runs from repo root and uses `.ansible/roles` as a roles search path; the hardening role must be discoverable without changing runtime inventory behavior.
   - Risk level: low
   - Behavior change: Adds a symlink so ansible-lint can resolve the role during local and CI validation without changing execution from `fabric-core/ansible`.

38. **Explicit confirmations (no scope bleed)**
   - Files affected: N/A (scope statement)
   - Reason: Hardening work must not alter the already-finalized bootstrap/TLS/inventory/Terraform contracts.
   - Risk level: low
   - Behavior change: Confirmed `bootstrap.yml` unchanged; TLS/CA/inventory/Terraform logic untouched; `ssh root@host` remains disabled and `ssh samakia@host` remains valid after hardening.

39. **Added break-glass / recovery runbook (docs-only)**
   - Files affected: `OPERATIONS_BREAK_GLASS.md`, `OPERATIONS.md`
   - Reason: Operators need a 03:00-safe procedure to recover access without violating platform contracts.
   - Risk level: low
   - Behavior change: Documentation only. Explicitly reaffirms: root SSH remains disabled, strict Proxmox TLS via internal CA (no insecure flags), no DNS dependency, and 2-phase Ansible (`bootstrap.yml` root-only; `harden.yml` as `samakia`/become).

40. **Formalized the promotion flow (image → template → env, Git-driven)**
   - Files affected: `fabric-core/packer/lxc/scripts/upload-lxc-template-via-api.sh`, `fabric-core/terraform/envs/samakia-prod/main.tf`, `fabric-core/terraform/envs/samakia-dev/main.tf`, `OPERATIONS_PROMOTION_FLOW.md`, `OPERATIONS.md`
   - Reason: Promotion must be explicit and reversible; environments must not implicitly “float” to the latest template; template registration must be immutable and API-token-based.
   - Risk level: medium
   - Behavior change: Environments pin a versioned `*-v<monotonic>.tar.gz` template path and validate it via `check` blocks; promotion/rollback becomes a deliberate Git change (bump/revert the pinned version); the upload script fails loudly if the template already exists (no silent overwrite).

41. **Stopped tracking local rootfs build artifacts in Git**
   - Files affected: `fabric-core/packer/lxc/ubuntu-24.04/ubuntu-24.04-lxc-rootfs.tar.gz`
   - Reason: Rootfs build outputs are large, time-variant artifacts and must not be committed; Git should track only the build pipeline and version pinning, not the produced images.
   - Risk level: low
   - Behavior change: The rootfs tarball is no longer tracked by Git (local copies remain ignored as build artifacts).

42. **Aligned `samakia-dev` Terraform required version with production**
   - Files affected: `fabric-core/terraform/envs/samakia-dev/versions.tf`
   - Reason: Keep deterministic tooling expectations across environments and CI.
   - Risk level: low
   - Behavior change: Terraform `>= 1.6.0` is now enforced in `samakia-dev` as well.

43. **Removed Proxmox root SSH/scp-based template import scripts**
   - Files affected: `fabric-core/packer/lxc/scripts/import-lxc-template.sh`, `fabric-core/packer/lxc/scripts/push-and-import-lxc-template.sh`, `OPERATIONS.md`
   - Reason: The promotion/upload contract is API-token-based and must not depend on `root@<node>` SSH/scp; the removed scripts violated least-privilege and encouraged out-of-band mutations.
   - Risk level: low
   - Behavior change: Operators are directed to the API upload flow (`upload-lxc-template-via-api.sh`) for template registration; no functional runtime behavior changes to Terraform/Ansible.

44. **Added read-only drift detection and unified audit report (Terraform + Ansible)**
   - Files affected: `ops/scripts/drift-audit.sh`
   - Reason: Operators need an auditable, GitOps-safe way to detect drift without auto-remediation or implicit applies.
   - Risk level: low
   - Behavior change: Adds a new read-only workflow that runs `terraform plan` (no apply) and `ansible-playbook playbooks/harden.yml --check --diff`, then writes a timestamped local report under `audit/` (not committed).

45. **Made Ansible inventory environment-selectable for auditing**
   - Files affected: `fabric-core/ansible/inventory/terraform.py`
   - Reason: Drift/audit must be environment-scoped (dev vs prod) without changing bootstrap/hardening behavior or introducing DNS dependencies.
   - Risk level: low
   - Behavior change: Inventory now accepts `FABRIC_TERRAFORM_ENV` to select `fabric-core/terraform/envs/<env>`; default behavior remains `samakia-prod` when unset.

46. **Ignored drift/audit outputs in Git and documented usage**
   - Files affected: `.gitignore`, `OPERATIONS.md`
   - Reason: Audit reports must be locally saved but never committed automatically; operators need a single documented command to run audits.
   - Risk level: low
   - Behavior change: `audit/` is now ignored by Git; `OPERATIONS.md` includes a minimal “Drift Detection & Audit” section pointing to `ops/scripts/drift-audit.sh`.

47. **Added Proxmox HA & failure-domain design + operator runbooks (docs-only)**
   - Files affected: `OPERATIONS_HA_FAILURE_DOMAINS.md`, `OPERATIONS.md`
   - Reason: HA must be explicit, reversible, and grounded in failure domains (node/rack/power/storage/network) with step-by-step recovery procedures; Terraform must not silently mutate cluster HA state.
   - Risk level: low
   - Behavior change: Documentation only. Explicitly confirms: bootstrap/TLS/inventory/promotion/drift contracts are unchanged; no auto-heal/auto-enable HA is introduced.

48. **Added compliance snapshots and signed audit exports (read-only)**
   - Files affected: `ops/scripts/compliance-snapshot.sh`, `ops/scripts/verify-compliance-snapshot.sh`, `ops/scripts/drift-audit.sh`, `OPERATIONS_COMPLIANCE_AUDIT.md`, `OPERATIONS.md`, `.gitignore`
   - Reason: Produce immutable, timestamped evidence bundles (Terraform drift + Ansible check) with offline-verifiable integrity and provenance (GPG signature).
   - Risk level: low
   - Behavior change: Adds `compliance/<env>/snapshot-<UTC>/` artifacts (ignored by Git) containing `metadata.json`, drift outputs, `manifest.sha256` and `manifest.sha256.asc`; no apply/remediation is introduced and no secrets are written.

49. **Made drift-audit output path overridable for evidence packaging**
   - Files affected: `ops/scripts/drift-audit.sh`
   - Reason: Compliance snapshots must embed drift outputs without writing into repo-global audit paths or mutating environment directories.
   - Risk level: low
   - Behavior change: `AUDIT_OUT_DIR` and `AUDIT_TIMESTAMP_UTC` can now be used to place drift outputs into a caller-controlled directory; default behavior remains unchanged.

50. **Implemented dual-control (two-person) signing for compliance snapshots (opt-in)**
   - Files affected: `ops/scripts/compliance-snapshot.sh`, `ops/scripts/verify-compliance-snapshot.sh`
   - Reason: Compliance evidence must be valid only with two independent approvals/signatures; single-signer mode remains supported for non-dual-control contexts.
   - Risk level: low
   - Behavior change: When `DUAL_CONTROL_REQUIRED` exists in a snapshot, verification requires both `manifest.sha256.asc.a` and `manifest.sha256.asc.b`. Snapshot generation can be opt-in dual-control via `COMPLIANCE_DUAL_CONTROL=1` + `COMPLIANCE_GPG_KEYS="FPR_A,FPR_B"`; single-signature mode remains the default.

51. **Added key custody and dual-control governance runbook**
   - Files affected: `OPERATIONS_KEY_CUSTODY_DUAL_CONTROL.md`, `OPERATIONS_COMPLIANCE_AUDIT.md`, `OPERATIONS.md`
   - Reason: Dual-control signing requires explicit roles, custody rules, rotation/revocation guidance, and a 03:00-safe procedure for staged signing and offline audit verification.
   - Risk level: low
   - Behavior change: Documentation only. Explicitly confirms: compliance snapshots remain read-only; no infra mutation, no auto-remediation, and no private keys in Git.

52. **Added optional RFC 3161 TSA notarization for compliance snapshots (time-of-existence proof)**
   - Files affected: `ops/scripts/compliance-snapshot.sh`, `ops/scripts/verify-compliance-snapshot.sh`, `OPERATIONS_EVIDENCE_NOTARIZATION.md`, `OPERATIONS_COMPLIANCE_AUDIT.md`, `OPERATIONS.md`
   - Reason: Provide cryptographic proof that a snapshot existed at or before a trusted UTC time, independent of local clocks; complements (does not replace) signer authority.
   - Risk level: low
   - Behavior change: When `COMPLIANCE_TSA_URL` + `COMPLIANCE_TSA_CA` are set, snapshots can produce `manifest.sha256.tsr` + `tsa-metadata.json` and verification checks the TSA token offline; defaults remain unchanged when TSA is not configured.

53. **Added application-level compliance overlay (controls + evidence model + runbook)**
   - Files affected: `COMPLIANCE_CONTROLS.md`, `COMPLIANCE_EVIDENCE_MODEL.md`, `OPERATIONS_APPLICATION_COMPLIANCE.md`, `OPERATIONS_COMPLIANCE_AUDIT.md`, `OPERATIONS.md`
   - Reason: Substrate compliance proves the platform is controlled; application compliance proves each workload’s controls and evidence are controlled and auditable without assuming Kubernetes.
   - Risk level: low
   - Behavior change: Documentation only. Defines control IDs, required evidence, and a signable evidence bundle model that reuses the existing signing/dual-control/TSA workflow.

54. **Added read-only helper for application evidence bundle generation**
   - Files affected: `ops/scripts/app-compliance-evidence.sh`
   - Reason: Operators need a boring, deterministic way to produce per-service evidence bundles (metadata + config fingerprints) without copying secrets or mutating systems.
   - Risk level: low
   - Behavior change: Adds a local evidence generator that hashes allowlisted files and refuses secret-like inputs; it does not sign, notarize, or execute remote commands by default.

55. **Added post-incident forensics framework (read-only)**
   - Files affected: `OPERATIONS_POST_INCIDENT_FORENSICS.md`, `COMPLIANCE_FORENSICS_EVIDENCE_MODEL.md`, `OPERATIONS.md`, `OPERATIONS_COMPLIANCE_AUDIT.md`
   - Reason: Incidents require fact-preserving evidence packets with chain-of-custody, deterministic packaging, and compatibility with existing signing/dual-control/TSA workflows.
   - Risk level: low
   - Behavior change: Documentation only. Defines collection scope, redaction guidance, packaging structure, and how to sign/notarize/verify forensics bundles offline without enabling root SSH.

56. **Added optional local forensics collector (read-only, non-destructive)**
   - Files affected: `ops/scripts/forensics-collect.sh`, `.gitignore`
   - Reason: Operators need a conservative, repeatable way to collect minimal system/process/network/package evidence and safe file hashes into a deterministic bundle.
   - Risk level: low
   - Behavior change: Adds a local collector that writes `forensics/<incident-id>/snapshot-<UTC>/` with `manifest.sha256` and refuses secret-like files by default; it does not sign, remediate, or execute remote actions.

### Items intentionally NOT changed (with justification)

- **No new tools or services**: remediation stayed within Packer, Terraform, Ansible, and existing scripts as required.
- **No HA automation added**: HA remains a conceptual layer; implementing it would add new features beyond the mandate.
- **No Kubernetes assumptions introduced**: Kubernetes scaffolding remains untouched; the fix scope stayed on the core LXC pipeline.
- **No CI platform changes**: only local scripts were made real; wiring to GitHub Actions is still pending and should be handled separately.
