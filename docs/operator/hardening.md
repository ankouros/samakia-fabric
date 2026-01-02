# Phase 11 Pre-Exposure Hardening Checklist

WARNING: This document is auto-generated. Source of truth: hardening/checklist.json

Generated (UTC): 2026-01-01T14:17:30Z
Phase: phase11-hardening
Scope: pre-exposure substrate hardening gate

## Contracts and Governance

Required acceptance markers and governance files must exist and Phase 12 must not be started.

- **contracts.markers.present** (HARD): Phase 11 acceptance markers are present.
  - Rationale: Hardening gate depends on prior Phase 11 acceptances and routing defaults.
  - Verification: `test -f acceptance/PHASE11_ACCEPTED.md && test -f acceptance/PHASE11_PART1_ACCEPTED.md && test -f acceptance/PHASE11_PART2_ACCEPTED.md && test -f acceptance/PHASE11_PART3_ACCEPTED.md && test -f acceptance/PHASE11_PART4_ACCEPTED.md && test -f acceptance/PHASE11_PART5_ROUTING_ACCEPTED.md`
  - Expected: All Phase 11 markers exist.
  - Status: PASS
- **contracts.required-fixes.clean** (HARD): REQUIRED-FIXES.md has no OPEN items.
  - Rationale: Open blockers must be resolved before pre-exposure hardening is accepted.
  - Verification: `! rg -n "OPEN" REQUIRED-FIXES.md`
  - Expected: No OPEN entries present.
  - Status: PASS
- **contracts.phase12.gating** (HARD): Phase 12 artifacts are absent.
  - Rationale: Phase 12 must not start before this hardening gate passes.
  - Verification: `test ! -f acceptance/PHASE12_ACCEPTED.md && test ! -f acceptance/PHASE12_ENTRY_CHECKLIST.md && ! rg -n "phase12" Makefile`
  - Expected: No Phase 12 markers or Make targets.
  - Status: PASS

## Identity and Access

Enabled contracts must not contain inline secrets and must reference secret_ref.

- **identity.no-inline-secrets** (HARD): Enabled contracts contain no inline secret keys.
  - Rationale: Secrets must never be stored in contracts; only secret_ref is allowed.
  - Verification: `! rg -n "(^|\s)(password|token|secret)\s*:\s" contracts/tenants/**/consumers/**/enabled.yml`
  - Expected: No secret-like keys in enabled contracts.
  - Status: PASS
- **identity.secret-ref-present** (HARD): Enabled contracts declare secret_ref.
  - Rationale: Secret references are required for tenant credentials and endpoints.
  - Verification: `rg -n "secret_ref" contracts/tenants/**/consumers/**/enabled.yml`
  - Expected: secret_ref is present in enabled contracts.
  - Status: PASS

## Tenant Isolation and Guardrails

Substrate execution guardrails and policies must exist and be wired.

- **tenant.guardrail-files** (HARD): Core guardrail files exist.
  - Rationale: Capacity and execute policy tooling is required for safe multi-tenant execution.
  - Verification: `test -f ops/substrate/capacity/capacity-guard.sh && test -f ops/substrate/validate-enabled-contracts.sh && test -f ops/substrate/common/execute-policy.yml && test -f ops/substrate/common/validate-execute-policy.sh`
  - Expected: All guardrail files are present.
  - Status: PASS
- **tenant.capacity-guard-wired** (HARD): Capacity guard is wired into the substrate dispatcher.
  - Rationale: Capacity must be enforced before apply or DR execute.
  - Verification: `rg -n "capacity-guard.sh" ops/substrate/substrate.sh`
  - Expected: capacity-guard.sh referenced in substrate dispatcher.
  - Status: PASS

## Capacity and Quotas

Capacity schema, templates, and validators must exist.

- **capacity.schema-template** (HARD): Capacity schema and template files exist.
  - Rationale: Capacity contracts are required for noisy-neighbor guardrails.
  - Verification: `test -f contracts/tenants/_schema/capacity.schema.json && test -f contracts/tenants/_templates/capacity.yml`
  - Expected: Capacity schema and template present.
  - Status: PASS
- **capacity.validator-present** (HARD): Capacity semantics validator exists.
  - Rationale: Capacity limits must be validated before apply or DR execute.
  - Verification: `test -f ops/substrate/capacity/validate-capacity-semantics.sh`
  - Expected: Capacity validator present.
  - Status: PASS

## HA and Failure Semantics

Enabled contract validation must exist to enforce HA and DR semantics.

- **ha.enabled-contract-validation** (HARD): Enabled contract validator exists.
  - Rationale: Enabled contract validation enforces HA-ready semantics.
  - Verification: `test -f ops/substrate/validate-enabled-contracts.sh`
  - Expected: Enabled contract validator present.
  - Status: PASS

## Disaster Recovery

DR dry-run scripts must exist for each provider.

- **dr.dryrun-scripts** (HARD): DR dry-run scripts exist for all supported providers.
  - Rationale: DR readiness must be assessed without mutation.
  - Verification: `test -f ops/substrate/postgres/dr-dryrun.sh && test -f ops/substrate/mariadb/dr-dryrun.sh && test -f ops/substrate/rabbitmq/dr-dryrun.sh && test -f ops/substrate/cache/dr-dryrun.sh && test -f ops/substrate/qdrant/dr-dryrun.sh`
  - Expected: All DR dry-run scripts present.
  - Status: PASS

## Observability and Drift

Substrate observability scripts must be present.

- **observability.scripts** (HARD): Observe and compare scripts exist.
  - Rationale: Hardening gate requires drift/observability checks to be available.
  - Verification: `test -f ops/substrate/observe/observe.sh && test -f ops/substrate/observe/compare.sh`
  - Expected: Observability scripts present.
  - Status: PASS

## Secrets and Evidence Hygiene

Secrets interface and evidence gitignore must be present.

- **secrets.interface-present** (HARD): Offline-first secrets interface exists.
  - Rationale: Credential handling relies on the Phase 5 secrets interface.
  - Verification: `test -f ops/secrets/secrets.sh`
  - Expected: Secrets interface present.
  - Status: PASS
- **secrets.evidence-gitignored** (HARD): Evidence and artifacts are gitignored.
  - Rationale: Evidence packets must never be committed.
  - Verification: `rg -n "^evidence/" .gitignore && rg -n "^artifacts/" .gitignore`
  - Expected: evidence/ and artifacts/ are gitignored.
  - Status: PASS

## Execution Safety

CI workflows must be read-only and apply must be manual.

- **execution.no-apply-pr-validate** (HARD): PR validation workflow has no apply steps.
  - Rationale: CI must remain read-only.
  - Verification: `! rg -n "terraform apply|tf.apply|substrate.apply|tenants.apply" .github/workflows/pr-validate.yml`
  - Expected: No apply commands in PR validation.
  - Status: PASS
- **execution.no-apply-pr-plan** (HARD): PR plan workflow has no apply steps.
  - Rationale: Plan workflows must remain read-only.
  - Verification: `! rg -n "terraform apply|tf.apply|substrate.apply|tenants.apply" .github/workflows/pr-tf-plan.yml`
  - Expected: No apply commands in PR plan workflow.
  - Status: PASS
- **execution.apply-manual** (HARD): Non-prod apply workflow is manual.
  - Rationale: Apply must require explicit manual triggering.
  - Verification: `test -f .github/workflows/apply-nonprod.yml && rg -n "workflow_dispatch" .github/workflows/apply-nonprod.yml`
  - Expected: apply-nonprod is manual.
  - Status: PASS

## Operator UX and Docs

Hardening gate must be documented and auto-generated docs must exist.

- **docs.cookbook-hardening** (HARD): Cookbook documents hardening gate commands.
  - Rationale: Operator workflows must be documented in the canonical cookbook.
  - Verification: `rg -n "phase11.hardening" docs/operator/cookbook.md`
  - Expected: Hardening gate commands documented in cookbook.
  - Status: PASS
- **docs.operations-hardening** (HARD): OPERATIONS.md references hardening gate.
  - Rationale: Operations index must point to the hardening gate.
  - Verification: `rg -n "phase11.hardening" OPERATIONS.md`
  - Expected: OPERATIONS.md references hardening gate.
  - Status: PASS
- **docs.hardening-generated** (HARD): Generated hardening doc exists.
  - Rationale: The checklist must be readable by operators without editing JSON.
  - Verification: `test -f docs/operator/hardening.md`
  - Expected: docs/operator/hardening.md exists.
  - Status: PASS

## Makefile Integration

Hardening gate targets must exist in Makefile.

- **makefile.hardening-entry-target** (HARD): Makefile includes phase11.hardening.entry.check target.
  - Rationale: Operators must have a single entry point for the hardening checklist.
  - Verification: `rg -n "phase11.hardening.entry.check" Makefile`
  - Expected: Makefile target exists.
  - Status: PASS
- **makefile.hardening-accept-target** (HARD): Makefile includes phase11.hardening.accept target.
  - Rationale: Operators must have a single acceptance gate for hardening.
  - Verification: `rg -n "phase11.hardening.accept" Makefile`
  - Expected: Makefile target exists.
  - Status: PASS
