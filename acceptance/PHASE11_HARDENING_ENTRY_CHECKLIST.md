# Phase 11 Pre-Exposure Hardening Gate Entry Checklist

Timestamp (UTC): 2026-01-01T13:38:44Z

## Criteria

## Contracts & Governance
- Marker present: acceptance/PHASE11_ACCEPTED.md
  - Command: test -f acceptance/PHASE11_ACCEPTED.md
  - Result: PASS
- Marker present: acceptance/PHASE11_PART1_ACCEPTED.md
  - Command: test -f acceptance/PHASE11_PART1_ACCEPTED.md
  - Result: PASS
- Marker present: acceptance/PHASE11_PART2_ACCEPTED.md
  - Command: test -f acceptance/PHASE11_PART2_ACCEPTED.md
  - Result: PASS
- Marker present: acceptance/PHASE11_PART3_ACCEPTED.md
  - Command: test -f acceptance/PHASE11_PART3_ACCEPTED.md
  - Result: PASS
- Marker present: acceptance/PHASE11_PART4_ACCEPTED.md
  - Command: test -f acceptance/PHASE11_PART4_ACCEPTED.md
  - Result: PASS
- Marker present: acceptance/PHASE11_PART5_ROUTING_ACCEPTED.md
  - Command: test -f acceptance/PHASE11_PART5_ROUTING_ACCEPTED.md
  - Result: PASS
- REQUIRED-FIXES.md has no OPEN items
  - Command: rg -n "OPEN" REQUIRED-FIXES.md
  - Result: PASS

## Identity & Access
- Enabled contracts contain no inline secrets
  - Command: rg -n "(^|\s)(password|token|secret)\s*:\s" contracts/tenants/**/consumers/**/enabled.yml
  - Result: PASS
- Enabled contracts declare secret_ref
  - Command: rg -n "secret_ref" contracts/tenants/**/consumers/**/enabled.yml
  - Result: PASS

## Tenant Isolation & Substrate Guardrails
- File present: ops/substrate/capacity/capacity-guard.sh
  - Command: test -f ops/substrate/capacity/capacity-guard.sh
  - Result: PASS
- File present: ops/substrate/validate-enabled-contracts.sh
  - Command: test -f ops/substrate/validate-enabled-contracts.sh
  - Result: PASS
- File present: ops/substrate/common/execute-policy.yml
  - Command: test -f ops/substrate/common/execute-policy.yml
  - Result: PASS
- File present: ops/substrate/common/validate-execute-policy.sh
  - Command: test -f ops/substrate/common/validate-execute-policy.sh
  - Result: PASS
- Capacity guard wired into substrate dispatcher
  - Command: rg -n "capacity-guard.sh" ops/substrate/substrate.sh
  - Result: PASS

## Capacity & Noisy-Neighbor
- File present: contracts/tenants/_schema/capacity.schema.json
  - Command: test -f contracts/tenants/_schema/capacity.schema.json
  - Result: PASS
- File present: contracts/tenants/_templates/capacity.yml
  - Command: test -f contracts/tenants/_templates/capacity.yml
  - Result: PASS
- File present: ops/substrate/capacity/validate-capacity-semantics.sh
  - Command: test -f ops/substrate/capacity/validate-capacity-semantics.sh
  - Result: PASS

## HA & Failure Semantics
- Enabled contract validation present
  - Command: test -f ops/substrate/validate-enabled-contracts.sh
  - Result: PASS

## Disaster Recovery Readiness
- DR dry-run script present: ops/substrate/postgres/dr-dryrun.sh
  - Command: test -f ops/substrate/postgres/dr-dryrun.sh
  - Result: PASS
- DR dry-run script present: ops/substrate/mariadb/dr-dryrun.sh
  - Command: test -f ops/substrate/mariadb/dr-dryrun.sh
  - Result: PASS
- DR dry-run script present: ops/substrate/rabbitmq/dr-dryrun.sh
  - Command: test -f ops/substrate/rabbitmq/dr-dryrun.sh
  - Result: PASS
- DR dry-run script present: ops/substrate/cache/dr-dryrun.sh
  - Command: test -f ops/substrate/cache/dr-dryrun.sh
  - Result: PASS
- DR dry-run script present: ops/substrate/qdrant/dr-dryrun.sh
  - Command: test -f ops/substrate/qdrant/dr-dryrun.sh
  - Result: PASS

## Observability & Drift
- Observability script present: ops/substrate/observe/observe.sh
  - Command: test -f ops/substrate/observe/observe.sh
  - Result: PASS
- Observability script present: ops/substrate/observe/compare.sh
  - Command: test -f ops/substrate/observe/compare.sh
  - Result: PASS

## Secrets & Sensitive Data
- Offline-first secrets interface present
  - Command: test -f ops/secrets/secrets.sh
  - Result: PASS
- Evidence directory is gitignored
  - Command: rg -n "^evidence/" .gitignore
  - Result: PASS

## Execution Safety
- PR workflow has no apply steps
  - Command: rg -n "terraform apply|tf.apply|substrate.apply|tenants.apply" /home/aggelos/samakia-fabric/.github/workflows/pr-validate.yml
  - Result: PASS
- PR workflow has no apply steps
  - Command: rg -n "terraform apply|tf.apply|substrate.apply|tenants.apply" /home/aggelos/samakia-fabric/.github/workflows/pr-tf-plan.yml
  - Result: PASS
- apply-nonprod workflow is manual
  - Command: rg -n "workflow_dispatch" .github/workflows/apply-nonprod.yml
  - Result: PASS

## Phase 12 Gating
- Phase 12 acceptance marker absent
  - Command: test ! -f acceptance/PHASE12_ACCEPTED.md
  - Result: PASS
- Phase 12 entry checklist absent
  - Command: test ! -f acceptance/PHASE12_ENTRY_CHECKLIST.md
  - Result: PASS
- No Phase 12 Makefile targets
  - Command: rg -n "phase12" Makefile
  - Result: PASS

## Operator UX & Docs
- Cookbook documents hardening gate
  - Command: rg -n "phase11.hardening" docs/operator/cookbook.md
  - Result: PASS
- Operations doc references hardening gate
  - Command: rg -n "phase11.hardening" OPERATIONS.md
  - Result: PASS

## Makefile Integration
- Makefile target present: phase11.hardening.entry.check
  - Command: rg -n "phase11.hardening.entry.check" Makefile
  - Result: PASS
- Makefile target present: phase11.hardening.accept
  - Command: rg -n "phase11.hardening.accept" Makefile
  - Result: PASS
