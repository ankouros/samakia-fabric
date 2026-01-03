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
#### Platform consumers (Phase 6 design)
- Consumer contract schema + ready/enabled manifests for kubernetes/database/message-queue/cache
- Phase 6 entry checklist + acceptance plan (design-only; no deployments)
- Consumer documentation skeleton under `docs/consumers/`

#### Platform consumers (Phase 6 Part 1)
- Read-only consumer validation suite (schema + semantics + HA readiness + disaster wiring)
- Consumer readiness evidence packets under `evidence/consumers/<type>/<variant>/<UTC>/`
- Phase 6 Part 1 acceptance marker: `acceptance/PHASE6_PART1_ACCEPTED.md`

#### Platform consumers (Phase 6 Part 2)
- Safe GameDay wiring (dry-run only) mapped to consumer disaster testcases
- Consumer bundle generation + validation (ports, firewall intents, storage, observability)
- CI PR validation extended with consumer checks + readiness/bundle artifacts
- Phase 6 Part 2 acceptance marker: `acceptance/PHASE6_PART2_ACCEPTED.md`

#### Platform consumers (Phase 6 Part 3)
- Controlled execute policy (allowlisted envs/actions; prod blocked; maintenance windows enforced)
- Consumer GameDay execute mode with guardrails + optional signed evidence
- Execute policy validation target + acceptance marker: `acceptance/PHASE6_PART3_ACCEPTED.md`

#### AI operations safety (Phase 7)
- AI operations policy + ADR (read-only default; guarded remediation)
- Plan review packets from Terraform plan artifacts (read-only)
- Safe-run allowlist with evidence wrapper packets
- Phase 7 acceptance marker: `acceptance/PHASE7_ACCEPTED.md`

#### AI-assisted analysis (Phase 16 Part 1)
- Ollama-only provider contract + deterministic routing policy (analysis-only)
- Policy gates for provider/routing enforcement (no external AI providers)
- Read-only AI CLI entrypoints for config checks and routing lookup
- Phase 16 Part 1 entry checklist + acceptance marker

#### AI-assisted analysis (Phase 16 Part 2)
- Qdrant + indexing contracts for tenant-isolated AI retrieval
- Offline-first indexing pipeline with fixtures, redaction, and evidence packets
- Policy gates for Qdrant/indexing + CI offline indexing step
- Phase 16 Part 2 entry checklist + acceptance marker

#### AI-assisted analysis (Phase 16 Part 3)
- Read-only MCP services for repo, evidence, observability, runbooks, and Qdrant
- Explicit allowlists, tenant isolation, and audit logging for every request
- MCP policy gate + doctor + entry/acceptance scripts and markers

#### AI-assisted analysis (Phase 16 Part 4)
- Structured AI analysis contract and guarded analysis tooling
- Deterministic prompts, evidence-bound reports, and redaction controls
- AI analysis policy gate, entry checklist, and acceptance marker

#### AI-assisted analysis (Phase 16 Part 5)
- AI governance model, stop rules, and risk ledger documentation
- Regression guardrail tests for AI safety + CI wiring
- Phase 16 closure entry checklist + Part 5 acceptance marker

#### AI-assisted analysis (Phase 16 Part 6)
- Unified AI ops entrypoint and evidence index tooling
- Ops regression tests for UX and evidence drift protection
- Phase 16 Part 6 entry checklist + acceptance marker

#### AI-assisted analysis (Phase 16 Part 7)
- AI invariants manifest + platform capability statement
- Invariant enforcement tests and phase-boundary policy gate
- Phase 16 Part 7 entry checklist + acceptance marker

#### VM golden images (Phase 8 design)
- ADR-0025 locking VM image contract scope (artifact-first; no VM lifecycle)
- VM image contract schema + example contracts (Ubuntu 24.04, Debian 12)
- Phase 8 entry checklist + acceptance plan (design-only; no builds)
- VM image docs skeleton under `docs/images/`

#### VM golden images (Phase 8 Part 1)
- Packer templates + Ansible hardening playbook for VM artifacts (Ubuntu 24.04, Debian 12)
- Validate-only qcow2 checks (cloud-init, SSH posture, pkg manifest, build metadata)
- VM image evidence packet scripts (build + validate)
- Phase 8 Part 1 acceptance marker: `acceptance/PHASE8_PART1_ACCEPTED.md`

#### VM golden images (Phase 8 Part 1.1)
- Local operator runbook + guarded wrapper for build/validate
- Tooling prerequisite checks + evidence verification helper
- Phase 8 Part 1.1 acceptance marker: `acceptance/PHASE8_PART1_1_ACCEPTED.md`

#### VM golden images (Phase 8 Part 1.2)
- Optional pinned toolchain container for builds/validation
- Toolchain wrapper + guarded Make targets
- Phase 8 Part 1.2 acceptance marker: `acceptance/PHASE8_PART1_2_ACCEPTED.md`

#### VM golden images (Phase 8 Part 2)
- Guarded Proxmox template registration tooling (token-only, allowlisted envs)
- Read-only template verification + evidence packets (register/verify)
- Phase 8 Part 2 acceptance marker: `acceptance/PHASE8_PART2_ACCEPTED.md`

#### Operator UX & doc governance (Phase 9)
- Operator command cookbook and safety model (`docs/operator/*`)
- Consumer catalog + guided flows (`docs/consumers/catalog.md`, `quickstart.md`, `variants.md`)
- Anti-drift doc tooling + CI gate (`make docs.operator.check`)
- Phase 9 acceptance marker: `acceptance/PHASE9_ACCEPTED.md`

#### Tutorials (Phase 1-2 onboarding)
- Tutorial index at `docs/tutorials/README.md` with required order.
- New tutorials for MinIO backend, DNS plane, and shared services under `docs/tutorials/`.

#### Tenant binding (Phase 10 design)
- ADR-0027 locking tenant = project binding model (design-only)
- Tenant contract schemas + templates + examples under `contracts/tenants/`
- Tenant docs skeleton under `docs/tenants/`
- Tenant validation tooling + CI gate (`make tenants.validate`)
- Phase 10 entry checklist + acceptance plan (design-only)

#### Tenant binding (Phase 10 Part 1)
- Policy/quotas + consumer binding validation for tenant contracts
- Deterministic, redacted tenant evidence packets (`evidence/tenants/...`)
- Phase 10 Part 1 entry checklist: `acceptance/PHASE10_PART1_ENTRY_CHECKLIST.md`
- Phase 10 Part 1 acceptance marker: `acceptance/PHASE10_PART1_ACCEPTED.md`

#### Tenant binding (Phase 10 Part 2)
- ADR-0028 locking guarded execute mode (offline-first, no CI execute)
- Execute policy allowlists + guarded plan/apply (`make tenants.execute.policy.check`, `make tenants.plan`, `make tenants.apply`)
- Offline-first credentials issuance under `ops/tenants/creds/`
- Tenant DR harness (`make tenants.dr.validate`, `make tenants.dr.run`)
- Phase 10 Part 2 entry checklist: `acceptance/PHASE10_PART2_ENTRY_CHECKLIST.md`
- Phase 10 Part 2 acceptance marker: `acceptance/PHASE10_PART2_ACCEPTED.md`

#### Substrate executors (Phase 11 design)
- ADR-0029 locking tenant-scoped substrate executors (design-only).
- Substrate DR taxonomy under `contracts/substrate/dr-testcases.yml`.
- Enabled executor schemas + templates for substrate consumers.
- Validation gate: `make substrate.contracts.validate`.
- Phase 11 acceptance marker: `acceptance/PHASE11_ACCEPTED.md`.

#### Substrate executors (Phase 11 Part 1)
- Plan-only executor scaffold and dispatcher (`ops/substrate/substrate.sh`).
- DR dry-run harness per provider with deterministic evidence packets.
- New targets: `substrate.plan`, `substrate.dr.dryrun`, `substrate.doctor`.
- Phase 11 Part 1 entry checklist: `acceptance/PHASE11_PART1_ENTRY_CHECKLIST.md`.
- Phase 11 Part 1 acceptance marker: `acceptance/PHASE11_PART1_ACCEPTED.md`.

#### Substrate executors (Phase 11 Part 2)
- Guarded execute policy allowlists for env/tenant/provider/variant.
- Apply/verify/DR execute scripts per provider (Postgres/MariaDB/RabbitMQ/Dragonfly/Qdrant).
- New targets: `substrate.apply`, `substrate.verify`, `substrate.dr.execute`.
- Phase 11 Part 2 entry checklist: `acceptance/PHASE11_PART2_ENTRY_CHECKLIST.md`.
- Phase 11 Part 2 acceptance marker: `acceptance/PHASE11_PART2_ACCEPTED.md`.

#### Substrate executors (Phase 11 Part 3)
- Tenant capacity contracts (`capacity.yml`) with schema/template/examples.
- Capacity validation + guardrails with deterministic evidence packets.
- Enabled contract SLO/failure semantics validation (single vs cluster).
- New targets: `tenants.capacity.validate`, `substrate.capacity.guard`, `substrate.capacity.evidence`.
- Phase 11 Part 3 entry checklist: `acceptance/PHASE11_PART3_ENTRY_CHECKLIST.md`.
- Phase 11 Part 3 acceptance marker: `acceptance/PHASE11_PART3_ACCEPTED.md`.

#### Substrate executors (Phase 11 Part 4)
- Runtime observability (read-only) + drift comparison for enabled contracts.
- Evidence packets under `evidence/tenants/**/substrate-observe`.
- CI gates: `substrate.observe`, `substrate.observe.compare`.
- Phase 11 Part 4 entry checklist: `acceptance/PHASE11_PART4_ENTRY_CHECKLIST.md`.
- Phase 11 Part 4 acceptance marker: `acceptance/PHASE11_PART4_ACCEPTED.md`.

#### Substrate executors (Phase 11 Part 5)
- Default drift alert routing aligned to environments (evidence-only, no delivery by default).
- Routing validation target: `make substrate.alert.validate`.
- Phase 11 Part 5 acceptance marker: `acceptance/PHASE11_PART5_ROUTING_ACCEPTED.md`.

#### Substrate hardening gate (Phase 11 pre-exposure)
- Pre-exposure hardening checklist is machine-verifiable (`hardening/checklist.json` + schema).
- Auto-generated entry checklist: `acceptance/PHASE11_HARDENING_ENTRY_CHECKLIST.md`.
- Pre-exposure hardening acceptance marker: `acceptance/PHASE11_HARDENING_JSON_ACCEPTED.md`.
- Gate targets: `make phase11.hardening.entry.check`, `make phase11.hardening.accept`.
- Evidence packets under `evidence/hardening/<UTC>/`.

#### Tenant bindings (Phase 12 Part 1)
- Binding contract schema + templates under `contracts/bindings/`.
- Binding validation + safety checks (`make bindings.validate`).
- Read-only connection manifest rendering (`make bindings.render`).
- Guarded apply entrypoint (`make bindings.apply`) with evidence output.
- Phase 12 Part 1 entry checklist: `acceptance/PHASE12_PART1_ENTRY_CHECKLIST.md`.
- Phase 12 Part 1 acceptance marker: `acceptance/PHASE12_PART1_ACCEPTED.md`.

#### Tenant bindings (Phase 12 Part 2)
- Binding secret shapes (keys only) under `contracts/secrets/shapes/`.
- Operator-controlled secret materialization + rotation hooks with redacted evidence.
- Policy gates for materialization/rotation wired into `make policy.check`.
- Phase 12 Part 2 entry checklist: `acceptance/PHASE12_PART2_ENTRY_CHECKLIST.md`.
- Phase 12 Part 2 acceptance marker: `acceptance/PHASE12_PART2_ACCEPTED.md`.

#### Tenant bindings (Phase 12 Part 3)
- Workload-side bindings verification (offline by default; guarded live mode).
- Verification evidence packets under `evidence/bindings-verify/<tenant>/<UTC>/`.
- Policy gate: `policy-bindings-verify.sh` wired into `make policy.check`.
- Phase 12 Part 3 entry checklist: `acceptance/PHASE12_PART3_ENTRY_CHECKLIST.md`.
- Phase 12 Part 3 acceptance marker: `acceptance/PHASE12_PART3_ACCEPTED.md`.

#### Tenant bindings (Phase 12 Part 4)
- Proposal schema + examples under `contracts/proposals/` and `examples/proposals/`.
- Intake/review/approval tooling under `ops/proposals/` (guarded; operator-controlled).
- Policy gate: `policy-proposals.sh` wired into `make policy.check`.
- Phase 12 Part 4 entry checklist: `acceptance/PHASE12_PART4_ENTRY_CHECKLIST.md`.
- Phase 12 Part 4 acceptance marker: `acceptance/PHASE12_PART4_ACCEPTED.md`.

#### Tenant drift awareness (Phase 12 Part 5)
- Drift taxonomy under `docs/drift/taxonomy.md`.
- Read-only drift detection tooling under `ops/drift/` (detect/classify/summary).
- Tenant drift summaries under `artifacts/tenant-status/<tenant>/`.
- Drift policy gate: `policy-drift.sh` wired into `make policy.check`.
- Phase 12 Part 5 entry checklist: `acceptance/PHASE12_PART5_ENTRY_CHECKLIST.md`.
- Phase 12 Part 5 acceptance marker: `acceptance/PHASE12_PART5_ACCEPTED.md`.

#### Tenant bindings (Phase 12 Part 6)
- Phase 12 release readiness packet tooling under `ops/release/phase12/`.
- One-page exposure flow: `docs/operator/phase12-exposure.md`.
- Regression tests under `ops/scripts/test-phase12/` wired into `fabric-ci/scripts/validate.sh`.
- Make targets: `phase12.readiness.packet`, `phase12.part6.entry.check`, `phase12.part6.accept`, `phase12.accept`.
- Phase 12 Part 6 acceptance marker: `acceptance/PHASE12_PART6_ACCEPTED.md`.
- Phase 12 acceptance marker: `acceptance/PHASE12_ACCEPTED.md`.

#### Milestone Phase 1–12 verification
- Milestone verification/lock tooling under `ops/milestones/phase1-12/`.
- Evidence packets under `evidence/milestones/phase1-12/<UTC>/`.
- Make targets: `milestone.phase1-12.verify`, `milestone.phase1-12.lock`.
- Milestone lock acceptance marker: `acceptance/MILESTONE_PHASE1_12_ACCEPTED.md` (self-hash; evidence-bound).

#### Production workload exposure (Phase 13 design)
- ADR-0031 defining governed exposure choreography (plan -> approve -> apply -> verify -> rollback).
- Exposure policy, approval, and rollback contracts under `contracts/exposure/`.
- Exposure operator docs and semantics under `docs/exposure/` and `docs/operator/exposure.md`.
- Phase 13 entry checklist and acceptance plan under `acceptance/`.

#### Production workload exposure (Phase 13 Part 1)
- Exposure policy evaluation tooling + plan-only evidence packets.
- Guarded `exposure.plan` and `exposure.plan.explain` targets (read-only).
- Phase 13 Part 1 entry checklist + acceptance marker.

#### Production workload exposure (Phase 13 Part 2)
- Guarded approval/apply/verify/rollback choreography (artifacts-only; no substrate provisioning).
- New targets: `exposure.approve`, `exposure.apply`, `exposure.verify`, `exposure.rollback`.
- Phase 13 Part 2 entry checklist + acceptance marker.
- Phase 13 acceptance marker.

#### Runtime operations and SLO ownership (Phase 14 design)
- ADR-0032 defining evidence-driven runtime operations and contractual SLO ownership.
- SLO contract schema under `contracts/slo/` with sample tenant SLO declarations.
- Runtime observation contract under `contracts/runtime-observation/`.
- Runtime signal taxonomy and incident lifecycle docs under `docs/runtime/`.
- Operator runtime ops and SLO ownership runbooks under `docs/operator/`.
- Phase 14 entry checklist + acceptance plan under `acceptance/`.

#### Runtime signal evaluation (Phase 14 Part 1)
- Read-only runtime evaluation engine under `ops/runtime/` (load, normalize, classify, redact, evidence).
- Deterministic evidence packets under `evidence/runtime-eval/<tenant>/<workload>/<UTC>/`.
- Operator status summaries under `artifacts/runtime-status/<tenant>/<workload>/`.
- Policy gate: `policy-runtime-eval.sh` wired into `make policy.check`.
- Make targets: `runtime.evaluate`, `runtime.status`, `phase14.part1.entry.check`, `phase14.part1.accept`.
- Phase 14 Part 1 entry checklist + acceptance marker.

#### SLO ingestion and evaluation (Phase 14 Part 2)
- Read-only SLO ingestion + evaluation tooling under `ops/slo/` (windows, error budgets, redaction, evidence).
- SLO evidence packets under `evidence/slo/<tenant>/<workload>/<UTC>/` with status summaries under `artifacts/slo-status/`.
- Alert readiness rules generated under `artifacts/slo-alerts/<tenant>/<workload>/` with delivery disabled by default.
- Policy gate: `policy-slo.sh` wired into `make policy.check`.
- Make targets: `slo.ingest.offline`, `slo.ingest.live`, `slo.evaluate`, `slo.alerts.generate`, `phase14.part2.entry.check`, `phase14.part2.accept`.
- Operator runbook updates for SLO measurement and runtime operations.

#### Alert delivery and incident surfacing (Phase 14 Part 3)
- Controlled alert delivery tooling under `ops/alerts/` with routing, formatting, redaction, and evidence packets.
- Incident record tooling under `ops/incidents/` with schema validation and evidence manifests.
- Alert evidence packets under `evidence/alerts/<tenant>/<UTC>/` and incident evidence under `evidence/incidents/<incident_id>/`.
- Policy gates: `policy-alerts.sh` and `policy-incidents.sh` wired into `make policy.check`.
- Make targets: `alerts.validate`, `alerts.deliver`, `incidents.open`, `incidents.update`, `incidents.close`, `phase14.part3.entry.check`, `phase14.part3.accept`.

#### Controlled self-service proposals (Phase 15 Part 1)
- Self-service proposal contract under `contracts/selfservice/` with example inputs.
- Read-only submit/validate/plan/review tooling with evidence under `evidence/selfservice/<tenant>/<proposal_id>/`.
- Policy gate `policy-selfservice.sh` wired into `make policy.check`; CI validates examples.
- Operator and tenant self-service docs plus Phase 15 Part 1 entry/accept targets.

#### Controlled self-service approval & delegation (Phase 15 Part 2 design)
- Proposal lifecycle state machine and execution mapping under `docs/selfservice/`.
- Approval and delegation schema examples under `contracts/selfservice/`.
- Audit model and operator approval/delegation runbook (design-only).
- Phase 15 Part 2 entry checklist and acceptance plan (design-only).

#### Controlled self-service autonomy guardrails (Phase 15 Part 3 design)
- Autonomy levels, risk budgets, and stop rules under `docs/selfservice/`.
- Guardrail mapping to Phase 11–14 and accountability model (design-only).
- Operator governance guidance and Phase 15 Part 3 entry/acceptance plan docs.

#### Controlled self-service UX + trust boundaries (Phase 15 Part 4 design)
- Tenant UX contract, trust boundary mapping, and UX safeguards (design-only).
- Autonomy unlock criteria and conflict resolution guidance.
- Operator UX guidance for self-service governance.

#### Controlled self-service governance closure (Phase 15 Part 5 design)
- Governance model, risk ledger, and exception framework (design-only).
- Phase interaction guarantees and Phase 15 acceptance plan/lock marker.

### Changed
#### Tenant binding validation
- Binding semantics validation now falls back to example tenant contracts when a top-level tenant directory lacks `tenant.yml` (supports SLO-only directories).

#### Phase 12 post-actions (hardening)
- Pinned base digests and apt snapshot sources for image builds; stamped `/etc/samakia-image-version` with provenance metadata.
- Introduced `RUNNER_MODE=ci|operator` to enforce non-interactive CI behavior and explicit inputs.
- Documented SSH trust rotation, networking determinism policy, runner modes, and template upgrade semantics.
- Updated milestone lock statement for Phase 13 readiness.
- Re-verified Milestone Phase 1–12 and refreshed the acceptance marker.
- Phase 12 validation allows the milestone invariant scan pattern without tripping the insecure TLS guard.
- Backfilled `acceptance/PHASE1_ACCEPTED.md` with a SHA256 self-hash for marker integrity.
- Invariant scans now normalize repo-relative paths and allowlist the milestone scan patterns.
- Recorded and closed the Phase 1–12 milestone verification blocker in `REQUIRED-FIXES.md`.
- Milestone wrapper now captures per-step stdout/stderr, preserves exit codes, and includes failure excerpts in summary evidence.

### Fixed
- Shared observability now satisfies HA placement requirements with an obs-2 node, updated edge backends, and expanded acceptance coverage.
- Loki configuration blocks structured metadata under v11 schemas and ensures data directories are owned by the Loki user.
- Shared bootstrap only targets VLAN nodes that still accept root SSH during first-time bootstraps.
- MinIO cluster nodes now receive chrony client configuration, and time-skew checks run concurrently to avoid false positives.
- Phase 12 readiness packet tests now run in CI mode to avoid GPG signing when ENV is prod.
- Milestone wrapper tests skip manifest signing in test mode to preserve exit semantics without GPG keys.
- Added milestone wrapper exit-semantics regression test.
- Recorded and resolved the MinIO backend smoke marker blocker for milestone verification in `REQUIRED-FIXES.md`.
- Milestone verification no longer forces `-backend=false` for `terraform init`, allowing backend smoke checks to confirm S3 initialization.
- Recorded the open shared observability policy blocker for milestone verification in `REQUIRED-FIXES.md`.

#### Security posture hardening (Phase 5)
- Offline-first secrets interface (optional Vault read-only mode)
- Guarded SSH key rotation workflows (operator + break-glass) with evidence packets
- Firewall profiles (default-off) with guarded apply and read-only checks
- Compliance profile evaluation mapped to control catalog (baseline/hardened)
- Phase 5 entry checklist and acceptance marker (self-hash; no secrets)

#### Ecosystem alignment
- Added repo-level contracts synced from samakia-specs and shared ecosystem baseline.
- Added home-directory Codex memory pointer in AGENTS.md.
- Added Session Log reminder in AGENTS.md.

#### GitOps & CI workflows (Phase 4)
- GitHub Actions workflows for PR validation, PR plan evidence, drift detection, app compliance, release readiness, and gated non-prod apply
- Policy-as-code gates (`ops/policy/*`) with `make policy.check` (terraform rules, secrets scanning, HA enforcement, docs updates)
- Evidence packet scripts:
  - `ops/scripts/drift-packet.sh`
  - `ops/scripts/app-compliance-packet.sh`
  - `ops/scripts/release-readiness-packet.sh`
- Phase 4 entry checklist: `acceptance/PHASE4_ENTRY_CHECKLIST.md`
- Phase 4 acceptance marker: `acceptance/PHASE4_ACCEPTED.md` (self-hash; no secrets)

#### Proxmox UI metadata
- Deterministic Proxmox tags for all Terraform-managed LXCs (semicolon-separated; prefix-encoded key/value schema)
  - Tag schema: `golden-vN;plane-<plane>;env-<env>;role-<role>` (Terraform-managed; no manual UI edits)
  - `golden-vN` derived from pinned template artifact name (`*-vN.tar.gz`), enforced via Terraform checks/preconditions
  - DNS/MinIO acceptance scripts verify tags via Proxmox API (strict TLS, token-only; secrets-safe)

#### Golden image automation
- Artifact-driven golden image auto-bump (no repo edits per version)
  - Version resolver: `ops/scripts/image-next-version.sh` (+ unit test `ops/scripts/test-image-next-version.sh`)
  - `make image.build` now builds next version by default; `VERSION=N` builds an explicit version without overwriting
  - `make image.build-next` prints max/next/artifact path and injects vars into Packer at runtime
  - `fabric-ci/scripts/validate.sh` runs the versioning unit test (no packer, no Proxmox)
- MinIO HA Terraform backend (Terraform + Ansible + acceptance, non-interactive)
  - Terraform env: `fabric-core/terraform/envs/samakia-minio/` (5 LXCs: `minio-edge-1/2`, `minio-1/2/3` with static IPs and pinned image version)
  - Proxmox SDN ensure script: `ops/scripts/proxmox-sdn-ensure-stateful-plane.sh` (zone `zminio`, vnet `vminio`, VLAN140 subnet `10.10.140.0/24`)
  - MinIO SDN acceptance tests: `ops/scripts/minio-sdn-accept.sh` + `ENV=samakia-minio make minio.sdn.accept` (read-only validation of stateful SDN plane + wiring signals)
  - MinIO cluster convergence checks: `ops/scripts/minio-convergence-accept.sh` + `ENV=samakia-minio make minio.converged.accept` (read-only runtime health + HA invariants after `minio.up`)
  - MinIO quorum-loss guard: `ops/scripts/minio-quorum-guard.sh` + `ENV=samakia-minio make minio.quorum.guard` (detect-only PASS/WARN/FAIL gate; blocks unsafe state migration and gates `dns.up`)
  - MinIO edge failure simulation hook: `ops/scripts/minio-edge-failure-sim.sh` + `make minio.failure.sim ENV=samakia-minio EDGE=minio-edge-1` (reversible stop/start of keepalived+haproxy on one edge; validates VIP continuity)
  - MinIO Terraform backend smoke test: `ops/scripts/minio-terraform-backend-smoke.sh` + `ENV=samakia-minio make minio.backend.smoke` (real terraform init+plan against S3 backend; strict TLS + lockfile verification; hard gate)
  - Ansible playbooks: `fabric-core/ansible/playbooks/state-backend.yml`, `fabric-core/ansible/playbooks/minio.yml`, `fabric-core/ansible/playbooks/minio-edge.yml`
  - Ansible roles: `fabric-core/ansible/roles/minio_cluster`, `fabric-core/ansible/roles/minio_edge_lb`
  - Runner bootstrap helper: `ops/scripts/backend-configure.sh` (local-only credentials + backend CA + HAProxy TLS pem; installs backend CA into host trust store with non-interactive sudo)
  - One-command automation: `make minio.up ENV=samakia-minio` + acceptance `make minio.accept` (`ops/scripts/minio-accept.sh`)
- DNS infrastructure substrate (Terraform + Ansible + acceptance, non-interactive)
  - Terraform env: `fabric-core/terraform/envs/samakia-dns/` (4 LXCs: `dns-edge-1/2`, `dns-auth-1/2` with static IPs and pinned image version)
  - Proxmox SDN ensure script: `ops/scripts/proxmox-sdn-ensure-dns-plane.sh` (zone `zonedns`, vnet `vlandns`, VLAN100 subnet `10.10.100.0/24`)
  - DNS SDN acceptance tests: `ops/scripts/dns-sdn-accept.sh` + `ENV=samakia-dns make dns.sdn.accept` (read-only validation of DNS SDN plane)
  - Ansible playbooks: `fabric-core/ansible/playbooks/dns.yml`, `fabric-core/ansible/playbooks/dns-edge.yml`, `fabric-core/ansible/playbooks/dns-auth.yml`
  - Ansible roles: `fabric-core/ansible/roles/dns_edge_gateway`, `fabric-core/ansible/roles/dns_auth_powerdns`
  - One-command automation: `make dns.up` + acceptance `make dns.accept` (`ops/scripts/dns-accept.sh`)
#### Shared control-plane services (Phase 2.1)
- Shared services SDN plane (VLAN120, `zshared`/`vshared`, subnet `10.10.120.0/24`, GW VIP `10.10.120.1`)
- Terraform env: `fabric-core/terraform/envs/samakia-shared/` (NTP edges, Vault HA, observability node)
- Ansible playbooks: `fabric-core/ansible/playbooks/shared.yml`, `shared-ntp.yml`, `shared-secrets.yml`, `shared-pki.yml`, `shared-observability.yml`
- Ansible roles: `ntp_chrony_server`, `ntp_chrony_client`, `shared_edge_gateway`, `vault_server`, `pki_vault`, `prometheus_stack`, `loki_stack`, `grafana`
- SDN ensure script: `ops/scripts/proxmox-sdn-ensure-shared-plane.sh` (token-only, strict TLS, apply on change)
- Acceptance scripts: `shared-sdn-accept.sh`, `shared-ntp-accept.sh`, `shared-vault-accept.sh`, `shared-pki-accept.sh`, `shared-obs-accept.sh`
- Orchestration targets: `make shared.up`, `make shared.accept`, and `make phase2.1.accept`
- Phase 2.1 entry checklist: `acceptance/PHASE2_1_ENTRY_CHECKLIST.md`
- Phase 2.1 acceptance marker: `acceptance/PHASE2_1_ACCEPTED.md` (read-only acceptance; no secrets)
- Governance: Phase 2 and Phase 2.1 marked completed in ROADMAP/REVIEW
- Phase 3 entry checklist: `acceptance/PHASE3_ENTRY_CHECKLIST.md` (status: NOT READY pending runtime verification)

#### Control-plane correctness (Phase 2.2)
- Observability ingestion acceptance: `ops/scripts/shared-obs-ingest-accept.sh` + `make shared.obs.ingest.accept` (Loki series must be queryable)
- Runtime invariants acceptance: `ops/scripts/shared-runtime-invariants-accept.sh` + `make shared.runtime.invariants.accept` (systemd active + enabled + restart policy)
- Phase 2.2 entry checklist: `acceptance/PHASE2_2_ENTRY_CHECKLIST.md`
- Phase 2.2 aggregate acceptance: `make phase2.2.accept` (read-only; no DNS dependency)
- Phase 2.2 acceptance marker: `acceptance/PHASE2_2_ACCEPTED.md` (read-only acceptance; no secrets)
#### HA semantics & failure domains (Phase 3 Part 1)
- HA semantics taxonomy and failure domain model: `OPERATIONS_HA_SEMANTICS.md`
- Placement policy source of truth: `fabric-core/ha/placement-policy.yml`
- Placement validator: `ops/scripts/ha/placement-validate.sh` + `make ha.placement.validate`
- Proxmox HA audit: `ops/scripts/ha/proxmox-ha-audit.sh` + `make ha.proxmox.audit`
- HA evidence snapshot: `ops/scripts/ha/evidence-snapshot.sh` + `make ha.evidence.snapshot`
- Phase 3 Part 1 acceptance: `make phase3.part1.accept`
- Phase 3 Part 1 acceptance marker: `acceptance/PHASE3_PART1_ACCEPTED.md`
#### GameDays & failure simulation (Phase 3 Part 2)
- GameDay framework scripts under `ops/scripts/gameday/` (precheck, evidence, postcheck)
- VIP failover simulation (dry-run by default; guarded execute)
- Service restart simulation (dry-run by default; guarded execute)
- GameDay runbook: `OPERATIONS_GAMEDAYS.md`
- Phase 3 Part 2 acceptance: `make phase3.part2.accept`
#### HA enforcement (Phase 3 Part 3)
- Placement enforcement hook: `ops/scripts/ha/enforce-placement.sh` + `make ha.enforce.check`
- Proxmox HA enforcement mode: `ops/scripts/ha/proxmox-ha-audit.sh --enforce`
- Enforcement unit test: `ops/scripts/ha/test-enforce-placement.sh` (offline, deterministic)
- Phase 3 Part 3 acceptance: `make phase3.part3.accept`
- Phase 3 Part 3 acceptance marker: `acceptance/PHASE3_PART3_ACCEPTED.md`
- Phase 1 operational hardening (remote state + runner bootstrapping + CI-safe orchestration)
- Remote Terraform backend initialization for MinIO/S3 with lockfiles (`ops/scripts/tf-backend-init.sh`; no DynamoDB; strict TLS)
- Runner host env management (`ops/scripts/runner-env-install.sh`, `ops/scripts/runner-env-check.sh`) with canonical env file `~/.config/samakia-fabric/env.sh` (chmod 600; presence-only output)
- Optional backend CA installer for MinIO/S3 (`ops/scripts/install-s3-backend-ca.sh`) to support strict TLS without insecure flags
- Environment parity guardrail (`ops/scripts/env-parity-check.sh`) enforcing dev/staging/prod structural equivalence
- New Terraform environment `fabric-core/terraform/envs/samakia-staging/` (parity with dev/prod)
- Inventory sanity guardrail for DHCP/IP determinism (`ops/scripts/inventory-sanity-check.sh`) + `make inventory.check`
- SSH trust lifecycle tools (`ops/scripts/ssh-trust-rotate.sh`, `ops/scripts/ssh-trust-verify.sh`) to support strict host key checking after replace/recreate
- Phase 1 acceptance suite (`ops/scripts/phase1-accept.sh` + `make phase1.accept`) to validate parity, runner env, inventory parse, and non-interactive Terraform plan
- Phase 1 acceptance marker: `acceptance/PHASE1_ACCEPTED.md` (hashed; no secrets)
- Phase 0 acceptance suite (`ops/scripts/phase0-accept.sh` + `make phase0.accept`) for foundation guardrails
- Phase 0 acceptance marker: `acceptance/PHASE0_ACCEPTED.md` (hashed; no secrets)
- Phase 2 entry checklist: `acceptance/PHASE2_ENTRY_CHECKLIST.md` (pre-flight PASS/FAIL record; no secrets)
- Phase 2 acceptance suite: `make phase2.accept` (read-only DNS + MinIO acceptance gate)
- Phase 2 acceptance marker: `acceptance/PHASE2_ACCEPTED.md` (self-hash included; no secrets)
- `OPERATIONS_LXC_LIFECYCLE.md` (replace-in-place vs blue/green runbook; DHCP/MAC determinism and SSH trust workflow)
- Future improvements tracked in `ROADMAP.md`
- Phase 3 entry runtime verification completed — READY (see `acceptance/PHASE3_ENTRY_CHECKLIST.md`)
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

### Fixed
- MinIO backend bootstrap invariant: `samakia-minio` always bootstraps with `terraform init -backend=false`, with explicit post-acceptance state migration
  - Guardrails: `make tf.backend.init ENV=samakia-minio` and `make tf.apply ENV=samakia-minio` fail loudly by design; use `minio.tf.plan/minio.tf.apply` instead
- MinIO convergence acceptance: parse `mc admin info` via server endpoint list and verify anonymous access with admin alias (prevents false negatives)
- MinIO bootstrap local-exec path invariant: local-exec provisioners use repo-root injection (`TF_VAR_fabric_repo_root`) and absolute script paths (no relative path assumptions)
- Deterministic script invocation invariant: repo scripts call other repo scripts via explicit repo root (no `cwd`/relative-path assumptions), and affected ops scripts fail loudly when `FABRIC_REPO_ROOT` is unset
- Makefile non-interactive apply invariant: Terraform `apply` uses `-auto-approve` when `CI=1` (prevents EOF failures in `make minio.up`/`make dns.up` and other non-interactive runs)
- Shared SDN acceptance parsing now uses correct JSON ingestion and fails on missing CT wiring (no SKIP in acceptance)
- Shared control-plane restart safety: `chrony`, `keepalived`, and `nftables` now enforce systemd restart policies via overrides

### Changed
- Refreshed Phase 1–12 milestone lock evidence to `evidence/milestones/phase1-12/2026-01-02T15:22:32Z` and updated the acceptance marker.
- Refreshed README and REVIEW narrative to align with current docs and a more humble, operator-focused tone.
- Migrated Codex remediation log into `CHANGELOG.md` (retired `codex-changelog.md`)
- Enforced Proxmox API token-only auth in Terraform envs and runner guardrails (password auth variables are no longer supported)
- Enabled strict SSH host key checking in Ansible (`fabric-core/ansible/ansible.cfg`), requiring explicit known_hosts rotation/enrollment on host replacement
- MinIO HA backend corrections (repo-wide): SDN zone/vnet renamed to `zminio`/`vminio` (≤ 8 chars), MinIO LAN VIP set to `192.168.11.101`, and edge management IPs aligned to avoid collisions (`minio-edge-1/2=192.168.11.102/103`, `dns-edge-1/2=192.168.11.111/112`)

### Fixed
- Excluded `<evidence>/legal-hold/` label packs from evidence `manifest.sha256` generation while keeping label packs independently signable/notarizable
- Ensured `ops/scripts/compliance-snapshot.sh` exports signer public keys in sign-only mode so verification works offline for add-on packs (e.g., legal hold records)
- Ensured Proxmox SDN VLAN planes are **applied** after creation/update (SDN config is not usable until cluster-wide apply completes)
- Made `fabric-ci/scripts/validate.sh` backend-credential-agnostic by isolating Terraform init/validate from any existing remote backend config (`TF_DATA_DIR` per env)
- DNS deployment correctness:
  - `make dns.up ENV=samakia-dns` bootstraps LAN-reachable `dns-edge-*` first, then VLAN-only `dns-auth-*` via ProxyJump
  - PowerDNS SQLite backend is initialized on first boot and packaged bindbackend config is disabled to avoid conflicting settings
  - `ops/scripts/dns-accept.sh` reads nftables rules via `sudo` to avoid false negatives

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
