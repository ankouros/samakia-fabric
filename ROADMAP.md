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

## Phase 3 — High Availability & Resilience

Goal: Enable resilient, multi-node deployments with realistic failure semantics.

### Planned
- Proxmox HA-aware patterns (workload classification: HA vs non-HA)
- Multi-node placement strategies + anti-affinity
- Storage abstraction patterns (NFS today, Ceph-ready)
- Failure-domain aware placement policy
- Routine GameDays (failure simulation) with evidence capture

Outcome:
- Controlled redundancy
- Clear failure handling semantics

---

## Phase 4 — GitOps & CI/CD Integration

Goal: Integrate infrastructure lifecycle with Git workflows safely.

### Planned
- Terraform plan via CI (read-only first) with human gatekeeping
- Policy-as-code checks (guardrails as mandatory gates)
- Pre-merge validation (fmt, validate, lint, security checks)
- Optional auto-apply for non-prod (explicitly opt-in)
- Drift detection workflows producing **signed evidence packets**
  - substrate drift packets
  - app compliance packets
  - release readiness packets

Outcome:
- Safer change management
- Audit-friendly operations with verifiable evidence

---

## Phase 5 — Advanced Security & Compliance

Goal: Strengthen security posture without sacrificing operability.

### Planned
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
