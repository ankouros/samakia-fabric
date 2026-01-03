# Samakia Fabric Contracts

Source of truth: `/home/aggelos/samakia-specs/repo-contracts/samakia-fabric.md`
Sync target: `/home/aggelos/samakia-fabric/CONTRACTS.md` (sync after updating specs).
Shared ecosystem contract: `/home/aggelos/samakia-specs/specs/base/ecosystem.yaml` (derived from samakia-fabric).

These contracts define non-negotiable expectations for infrastructure design, security, and operations.
Any change that violates a contract must be redesigned before merging.

## Shared Ecosystem Contract

### Design

- Infrastructure as code is the source of truth.
- Replace over repair; rebuild preferred when drift or failure occurs.
- Immutability by default for images and infrastructure identity.
- Clear responsibility boundaries between infrastructure, platform, and applications.
- Determinism over opaque automation; explicit workflows preferred.
- Explicit over implicit; defaults and assumptions must be visible.
- Documentation is part of the system and required for support.
- Git defines desired state; recovery flows from Git to reality.

### Security

- Least privilege by default; delegated access instead of shared root.
- Key-based authentication only; disable password auth wherever possible.
- No secrets in Git; secrets must come from Vault or external managers.
- Assume breach; design for containment, detection, and recovery.
- Audit logging and evidence retention are mandatory for operational actions.

### Entry Points

- `README.md`, `AGENTS.md`, `SECURITY.md`, `OPERATIONS.md`, `CONTRACTS.md`, `ROADMAP.md`, `CHANGELOG.md`.
- `docs/README.md` for documentation navigation.

### Acceptance

- Every repo defines an acceptance entrypoint for changes (Make target, script, or test suite).
- Acceptance runs are deterministic and non-interactive by default.
- Evidence of acceptance runs is recorded without secrets.
- Docs, contracts, and changelog/roadmap are updated with behavior changes.

### Alignment

- Update samakia-specs first, then sync into each repo.
- Evaluate contracts across samakia-fabric, samakia-platform, and pTerminal on every prompt.

## Fabric Contract

- Packer builds golden images only; no users, keys, or environment logic baked in.
- Golden image inputs are reproducible: base images pinned by digest, apt sources use snapshot mirrors, and `/etc/samakia-image-version` includes image_name, image_version, build_utc, git_sha, and packer_template_id.
- Terraform manages infrastructure lifecycle only; no provisioning or OS config.
- Ansible handles OS policy and user access; it must remain idempotent.
- Proxmox automation uses delegated users; `root@pam` is forbidden for automation.
- LXC feature flags are immutable post-creation; storage selection is explicit.
- SSH is key-only; root SSH is temporary for bootstrap only.
- SSH host key rotation is mandatory after replace/recreate; strict host key checking must remain enabled with out-of-band fingerprint verification.
- Tier-0 network identity is deterministic: MAC pinning or DHCP reservations are required, and IP cutovers must be documented and evidence-backed.
- Shared VLAN IP/VIP allocation is contract-governed (`contracts/network/ipam-shared.yml`); IPs and VIPs must be allocated exclusively from that contract and never guessed.
- Phase acceptance requires `make phase<N>.accept` (or phase-equivalent), evidence recording, and acceptance markers.
- AI operations are read-only by default; any remediation requires explicit guards and evidence packets.
- AI-assisted analysis is advisory-only: Ollama-only provider, deterministic routing, no external providers, and no execution or mutation paths.
- AI context access is read-only and tenant-scoped (MCP + Qdrant); indexing and analysis runs must emit evidence packets and remain CI-safe (offline/stub by default).
- AI invariants are codified in `contracts/ai/INVARIANTS.md`; any expansion of AI capabilities requires a new phase, ADR, and acceptance plan.
- VM golden images are contract-governed; canonical reference is storage_path + sha256; Fabric does not manage VM lifecycle.
- Operator UX is a first-class contract: `docs/operator/cookbook.md` is canonical, and operator-visible commands must be documented or explicitly waived by policy.
- Template upgrades are replace/blue-green only; Terraform never upgrades existing CTs in-place.
- Runner mode is a contract: `RUNNER_MODE=ci|operator` (default `ci`); CI mode forbids prompts and requires explicit inputs.
- Tenant bindings and substrate executor contracts are metadata-only by default; enabled.yml is contract-first and execution is always guarded, auditable, and opt-in.
- Binding secret materialization and rotation are guarded and evidence-backed; Vault is default and file backend is an explicit exception; `secret_ref` only with no secrets in Git.
- Substrate runtime observability and drift classification are read-only; evidence is mandatory and drift never auto-remediates or fails CI by itself.
- Drift alert routing defaults are evidence-only; external delivery is disabled unless explicitly enabled and allowed.
- Shared observability must satisfy HA policy: replicas >= 2, anti_affinity = true, and placement across at least two hosts.
- Shared observability policy is contract-bound under `contracts/observability/policy.yml` and enforced by repo validators (CI + acceptance fail on violation).
- Pre-exposure substrate hardening must pass before Phase 12 workload exposure; acceptance marker and evidence are mandatory.
- Phase 12 workload exposure requires a redacted release readiness packet and acceptance markers (Part 6 + overall); CI remains read-only.
- Phase 13 exposure is governed (plan -> approve -> apply -> verify -> rollback); prod requires change windows and signed evidence; CI remains read-only.
- Milestone Phase 1–12 verification requires deterministic end-to-end evidence packets, `make milestone.phase1-12.verify`, `make milestone.phase1-12.lock`, and an acceptance marker with a self-hash; CI remains read-only.
