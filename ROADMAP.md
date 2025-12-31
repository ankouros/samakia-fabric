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

### Planned
- Kubernetes-ready primitives (explicitly optional and guarded)
- Database service patterns
- Message queue patterns
- Observability stack foundations
- Consumer-facing platform documentation

Outcome:
- Samakia Fabric as a substrate, not a destination

---

## Phase 7 — AI-Assisted Operations

Goal: Enable safe, bounded AI participation.

### Planned
- Explicit agent task boundaries & refusal rules
- Automated plan review workflows (read-only by default)
- Controlled remediation (explicit opt-in, always audited)
- Decision enforcement via ADRs / runbooks / policy checks
- AI-readable runbooks + “03:00-safe” operational scripts

Outcome:
- Reduced cognitive load
- Safer automation at scale

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
