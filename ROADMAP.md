# Samakia Fabric – Roadmap

This roadmap outlines the **planned evolution** of Samakia Fabric.

It is not a promise.
It is a **directional guide** based on real operational priorities.

Dates are indicative.
Correctness and stability take precedence over speed.

---

## Guiding Principles

All roadmap items must:
- Respect existing architecture decisions
- Preserve security guarantees
- Avoid breaking changes without explicit versioning
- Remain operable by humans and AI agents
- Prefer **deterministic**, **auditable** workflows over convenience

Anything that violates these principles is out of scope.

---

## Phase 0 — Foundation (COMPLETED ✅)

Goal: Establish a solid, production-grade base.

### Completed (canonical)
- Proxmox-based infrastructure model (LXC-first)
- Golden image pipeline (Packer) with **monotonic immutable versioning** (`*-vN.tar.gz`)
- Upload of LXC templates via **Proxmox API token only** (no SSH/root on Proxmox)
- Terraform modules with Proxmox 9 guardrails
  - Provider pinning enforcement
  - Forbidden providers blocked
  - SSH key injection via `ssh_public_keys`
- **Strict Proxmox TLS** trust model (internal CA)
  - Host CA installer + guardrails checks (no insecure TLS flags)
- Ansible **2-phase** model
  - Phase-1 bootstrap: root-only minimal (CA trust, operator user + keys + sudo, disable root SSH)
  - Phase-2 hardening: operator-based (`samakia` + become), container-safe baseline
- Pre-commit / CI guardrails
  - terraform fmt/validate
  - ansible-lint
  - shellcheck
  - gitleaks
  - custom Terraform provider pinning hook
- Operations & lifecycle documentation set (production-grade)
  - Promotion flow (image → template → env)
  - Break-glass / recovery
  - HA failure domains + GameDays simulation
  - Drift audit reporting (read-only)
  - Pre-release readiness (Go/No-Go)
  - Threat modeling (STRIDE + trust boundaries)
- Compliance / evidence substrate (auditor-grade)
  - Signed compliance snapshots (sha256 manifest + GPG signatures)
  - Dual-control signing (2-person rule)
  - TSA notarization (RFC3161) as opt-in
  - Offline verification tools
  - Legal hold / retention labels (independent packs)
  - Application compliance overlay & evidence model
  - Post-incident forensics framework (read-only collector + chain-of-custody model)

Status: **Stable / Production usable**

---

## Phase 1 — Operational Hardening (COMPLETED ✅)

Goal: Make day-2 operations safer, more deterministic, and less error-prone.

### Completed (canonical)
- Remote Terraform state backend (MinIO/S3) with locking (`use_lockfile = true`) and strict TLS (no secrets in Git)
- Explicit environment separation with parity checks (`samakia-dev`, `samakia-staging`, `samakia-prod`)
- Deterministic runner host bootstrapping:
  - canonical env file: `~/.config/samakia-fabric/env.sh` (chmod 600)
  - runner install/check scripts (presence-only output; strict TLS + token-only)
- CI-safe non-interactive defaults for Terraform targets (`-input=false`, lock timeout, no prompts in `CI=1`)
- LXC lifecycle guard improvements:
  - replace-in-place and blue/green runbook + make guidance targets (no auto-apply)
- SSH trust lifecycle hardening:
  - strict known_hosts rotation workflow (no `StrictHostKeyChecking` disablement)
- DHCP/MAC determinism + inventory sanity checks:
  - loud failure on pinned IP mismatches; warning-only on unpinned IP discovery
- Inventory validation target (`make inventory.check`) and safe redaction guarantees (no token leakage)

Outcome:
- Reduced operator error
- Safer concurrent operations
- Faster recovery from expected “sharp edges” (known_hosts, DHCP flips)

---

## Phase 2 — Networking & Platform Primitives

Goal: Establish reusable infrastructure building blocks.

Status: COMPLETED ✅

### Completed (canonical)
- Proxmox SDN integration (guarded, applied after changes)
- DNS infrastructure plane (SDN VLAN + VIP-based edge/gateway pattern)
- MinIO backend plane (stateful SDN + VIP front door)
- Load balancer primitives (HAProxy / Keepalived patterns)
- Standard tagging/labeling conventions across CT/VM/network objects
- SDN + service acceptance gates (read-only)

Outcome:
- Predictable internal networking
- Reusable patterns across projects

---

## Phase 2.1 — Shared Control Plane Services

Goal: Provide internal time, PKI, secrets, and observability as reusable primitives.

Status: COMPLETED ✅

### Completed (canonical)
- Shared services SDN plane (VLAN120, `zshared`/`vshared`, subnet `10.10.120.0/24`, GW VIP `10.10.120.1`)
- Shared edge VIPs on LAN:
  - NTP: `192.168.11.120` (UDP/123)
  - Vault: `192.168.11.121` (TLS/8200)
  - Observability: `192.168.11.122` (TLS/3000, 9090, 9093, 3100)
- Internal time authority (chrony servers) + client policy
- Vault HA (raft) with bootstrap CA + Vault PKI issuance for shared services
- Observability substrate (Prometheus, Alertmanager, Loki, Grafana)
- Read-only acceptance gates + one-command deployment (`make shared.up` / `make shared.accept`)
- Phase 2.1 acceptance locked (`acceptance/PHASE2_1_ACCEPTED.md`)

Outcome:
- Shared control-plane services are deterministic, TLS-validated, and ready for reuse

---

## Phase 2.2 — Control Plane Correctness & Invariants

Goal: Enforce functional correctness for shared control-plane services beyond reachability.

Status: COMPLETED ✅

### Scope (canonical)
- Loki ingestion must be verifiable (queryable series present).
- Shared services must be active + enabled with restart safety (systemd readiness).
- Acceptance scripts are binary PASS/FAIL (no SKIP).
- Strict TLS and token-only Proxmox remain unchanged.
- No DNS dependency for acceptance (VIP IPs only).

Outcome:
- Shared services are not just up; they are **functionally correct**.

---

## Phase 3 — High Availability & Resilience (COMPLETED ✅)

Goal: Enable resilient, multi-node deployments with realistic failure semantics.

### Part 1 — HA Semantics & Failure Domains (COMPLETED)
- HA tiers and failure domain taxonomy documented
- Placement policy + validation (anti-affinity, explicit replicas)
- Proxmox HA audit guardrails (policy-aligned)
- Read-only evidence snapshot tooling (cluster/VIP/service readiness)

### Part 2 — GameDays & Failure Simulation (COMPLETED)
- GameDay framework (precheck → evidence → action → postcheck)
- VIP failover simulation (guarded, safe by default)
- Service restart simulation (guarded, safe by default)
- Dry-run acceptance gate (`make phase3.part2.accept`)

### Part 3 — HA Enforcement (COMPLETED)
- Placement policy enforcement before Terraform plan/apply (`make ha.enforce.check`)
- Proxmox HA enforcement mode with explicit override guardrails
- Phase 3 Part 3 acceptance gate (`make phase3.part3.accept`)

Outcome:
- Controlled redundancy
- Clear failure handling semantics

---

## Phase 4 — GitOps & CI/CD Integration

Goal: Integrate infrastructure lifecycle with Git workflows safely.

### Completed ✅
- Terraform plan via CI (read-only first) with human gatekeeping
- Policy-as-code checks (guardrails as mandatory gates)
- Pre-merge validation (fmt, validate, lint, security checks)
- Optional auto-apply for non-prod (explicitly opt-in)
- Drift detection workflows producing **signed evidence packets**
  - substrate drift packets
  - app compliance packets
  - release readiness packets
- Acceptance marker: `acceptance/PHASE4_ACCEPTED.md`

Outcome:
- Safer change management
- Audit-friendly operations with verifiable evidence

---

## Phase 5 — Advanced Security & Compliance (COMPLETED ✅)

Goal: Strengthen security posture without sacrificing operability.

### Completed (canonical)
- Secrets manager integration (optional; must preserve offline operability)
- SSH key rotation workflows (operator keys + break-glass policy)
- Host firewall patterns (container-safe, default-off unless explicitly enabled)
- Enhanced audit logging guidance
- Compliance profiles (baseline → hardened profiles) mapped to control catalog

Outcome:
- Stronger security guarantees
- Clear incident response paths and custody

---

## Phase 6 — Platform Consumers

Goal: Make Samakia Fabric consumable by higher-level platforms.

### Part 1 — Consumer Contracts & Validation (COMPLETED ✅)
- Contract schema + ready/enabled manifests for kubernetes/database/message-queue/cache
- Contract validation (schema + semantics) with HA readiness + disaster wiring checks
- Consumer readiness evidence packets (read-only)
- Acceptance marker: `acceptance/PHASE6_PART1_ACCEPTED.md`

### Part 2 — GameDay Wiring & Bundles (COMPLETED ✅)
- SAFE GameDay wiring (dry-run only) mapped to consumer testcases
- Consumer bundles (ports, storage, firewall intents, observability labels)
- CI PR validation includes consumer checks + readiness/bundle artifacts
- Acceptance marker: `acceptance/PHASE6_PART2_ACCEPTED.md`

### Part 3 — Controlled Execute Mode (COMPLETED ✅)
- Execute allowlists (dev/staging only; prod blocked)
- Maintenance window enforcement + operator reason
- Optional signing for execute-mode evidence
- Acceptance marker: `acceptance/PHASE6_PART3_ACCEPTED.md`

Phase 6 is **complete**. Additional consumer patterns (ready/enabled variants)
are tracked as future roadmap items and must not expand Phase 6 scope.

Outcome:
- Samakia Fabric as a substrate, not a destination

---

## Phase 7 — AI-Assisted Operations (COMPLETED ✅)

Goal: Enable safe, bounded AI participation.

### Completed (canonical)
- AI operations policy + ADR (read-only default, guarded remediation)
- Plan review packets from Terraform plan artifacts (read-only)
- Safe-run allowlist with evidence wrapper packets
- AI-readable runbooks and format validation
- Phase 7 acceptance marker: `acceptance/PHASE7_ACCEPTED.md`

Outcome:
- Reduced cognitive load
- Safer automation at scale

---

## Phase 8 — VM Golden Image Contracts

Goal: Introduce VM golden image contracts as immutable artifacts (no VM lifecycle).

### Part 1 (COMPLETED ✅)
- Packer templates + Ansible hardening playbook for Ubuntu 24.04 and Debian 12
- Validate-only qcow2 checks (cloud-init, SSH posture, pkg manifest, build metadata)
- Evidence packet scripts (build + validate)
- Acceptance marker: `acceptance/PHASE8_PART1_ACCEPTED.md`

### Part 1.1 (COMPLETED ✅)
- Local operator runbook for build/validate
- Safe wrapper scripts + tooling checks
- Acceptance marker: `acceptance/PHASE8_PART1_1_ACCEPTED.md`

### Part 1.2 (COMPLETED ✅)
- Optional pinned toolchain container
- Toolchain wrapper + guarded Make targets
- Acceptance marker: `acceptance/PHASE8_PART1_2_ACCEPTED.md`

### Part 2 (COMPLETED ✅)
- Guarded Proxmox template registration tooling (token-only; allowlisted envs)
- Read-only template verification + evidence packets
- Acceptance marker: `acceptance/PHASE8_PART2_ACCEPTED.md`

Non-scope:
- No VM provisioning or scaling
- No infrastructure mutation

---

## Phase 9 — Operator UX & Doc Governance

Goal: Provide a canonical operator UX layer with anti-drift documentation gates.

Status: COMPLETED ✅

### Completed (canonical)
- Operator command cookbook (`docs/operator/cookbook.md`) as canonical source
- Operator safety model + evidence guidance docs
- Consumer UX catalog + quickstart + variants
- Anti-drift doc tooling + CI gate (`make docs.operator.check`)
- Phase 9 acceptance marker: `acceptance/PHASE9_ACCEPTED.md`

Non-scope:
- No infrastructure deployment or mutation
- No provisioning or lifecycle changes

---

## Phase 10 — Tenant = Project Binding (Design)

Goal: Contract-first tenant model so projects consume stateful primitives
without embedding stateful lifecycle into their own Kubernetes.

Status: COMPLETED ✅

### Completed (canonical)
- ADR-0027 locking tenant = project binding model
- Tenant contract schemas + templates + examples under `contracts/tenants/`
- Tenant documentation skeleton under `docs/tenants/`
- Validation tooling + CI gate (`make tenants.validate`)
- Phase 10 entry checklist: `acceptance/PHASE10_ENTRY_CHECKLIST.md`
- Acceptance plan: `acceptance/PHASE10_ACCEPTANCE_PLAN.md`

Non-scope:
- No provisioning or apply paths
- No secrets creation or infra mutation

---

## Phase 10 Part 1 — Tenant Contract Operations

Goal: Enforce tenant contracts and produce deterministic evidence packets
without provisioning any runtime services.

Status: COMPLETED ✅

### Completed (canonical)
- Policy/quotas and consumer binding validation
- Evidence packet generation for tenant contracts
- Phase 10 Part 1 entry checklist: `acceptance/PHASE10_PART1_ENTRY_CHECKLIST.md`
- Phase 10 Part 1 acceptance marker: `acceptance/PHASE10_PART1_ACCEPTED.md`

Non-scope:
- No provisioning or apply paths
- No secrets issuance or infrastructure mutation

---

## Phase 10 Part 2 — Tenant Execute Mode (Guarded)

Goal: Introduce guarded execute mode for tenant bindings while remaining
offline-first and CI-safe.

Status: COMPLETED ✅

### Completed (canonical)
- Execute policy allowlists + validation (`make tenants.execute.policy.check`)
- Guarded plan/apply flows (`make tenants.plan`, `make tenants.apply`)
- Offline-first credentials issuance (`ops/tenants/creds/*`)
- Tenant DR harness with dry-run/execute modes (`make tenants.dr.validate`, `make tenants.dr.run`)
- Phase 10 Part 2 entry checklist: `acceptance/PHASE10_PART2_ENTRY_CHECKLIST.md`
- Phase 10 Part 2 acceptance marker: `acceptance/PHASE10_PART2_ACCEPTED.md`

Non-scope:
- No provisioning of DB/MQ/Cache/Vector services
- No secrets committed to Git
- No CI execution of guarded apply paths

---

## Phase 11 — Tenant-Scoped Substrate Executors (Design)

Goal: Define contract-first substrate executor semantics for tenant-enabled
stateful primitives (no execution).

Status: COMPLETED ✅

### Completed (canonical)
- ADR-0029 locking tenant-scoped executor contract model (design-only).
- Substrate DR taxonomy under `contracts/substrate/dr-testcases.yml`.
- Enabled executor schemas + templates for substrate consumers.
- Validation gate: `make substrate.contracts.validate`.
- Phase 11 entry checklist + acceptance marker: `acceptance/PHASE11_ACCEPTED.md`.

Non-scope:
- No provisioning or apply paths
- No secrets creation or infra mutation

---

## Non-Goals

The following are explicitly NOT goals:

- Becoming a managed service
- Supporting every hypervisor
- Abstracting away Proxmox specifics
- Hiding infrastructure complexity
- Optimizing for beginners

Samakia Fabric is built for operators who value control.

---

## Versioning Strategy (Planned)

- Semantic versioning for repository releases
- Major versions may introduce breaking changes
- Golden images versioned independently (monotonic, immutable)
- Terraform modules versioned explicitly

---

## How This Roadmap Evolves

This roadmap is:
- Reviewed periodically
- Updated as real needs emerge
- Driven by operational experience

New roadmap items must:
- Reference existing ADRs
- Justify their necessity
- Clearly state trade-offs

---

## Final Note

Samakia Fabric is designed to grow **deliberately**.

If a feature does not improve:
- Safety
- Clarity
- Operability
- Auditability

It does not belong on this roadmap.
