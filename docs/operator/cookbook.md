# Operator Command Cookbook

This cookbook is the **canonical operator source**. Commands here are copy/paste friendly.

All tasks follow a consistent template.

---

## Platform posture & safety model

### Task: Confirm safety posture

#### Intent
Confirm read-only default, execute guards, and evidence expectations.

#### Preconditions
- Repo cloned locally
- `FABRIC_REPO_ROOT` set by Makefile or exported

#### Command
```bash
make policy.check
```

#### Expected result
Policy checks pass and no guards are bypassed.

#### Evidence outputs
None (policy output only).

#### Failure modes
- Policy failure due to missing docs or guardrails

#### Rollback / safe exit
Stop and fix policy failures; do not proceed with mutations.

---

## Daily operations

### Task: Validate repository state

#### Intent
Run lint and validation gates before operational changes.

#### Preconditions
- Runner env configured
- `CI=1` if running in CI

#### Command
```bash
pre-commit run --all-files
bash fabric-ci/scripts/lint.sh
bash fabric-ci/scripts/validate.sh
```

#### Expected result
All checks PASS.

#### Evidence outputs
Validation logs only (no artifacts generated).

#### Failure modes
- Lint/validate failures for scripts or configs

#### Rollback / safe exit
Stop and remediate failures.

### Task: Rotate SSH known_hosts after replace/recreate

#### Intent
Maintain strict SSH checking while rotating host keys after rebuilds.

#### Preconditions
- Container was replaced or rebuilt
- Out-of-band console access for fingerprint verification

#### Command
```bash
ssh-keygen -R <host-or-ip>
ssh <user>@<host-or-ip>
```

#### Expected result
You confirm the new fingerprint out-of-band and accept the new key. See `docs/operator/ssh-trust.md`.

#### Evidence outputs
None (local known_hosts update only).

#### Failure modes
- Accepting a fingerprint without out-of-band verification

#### Rollback / safe exit
Abort the connection, re-verify the fingerprint, and retry.

### Task: Review networking determinism policy before replacement

#### Intent
Confirm MAC pinning and DHCP reservations for tier-0 services.

#### Preconditions
- Tier of service identified (tier-0/tier-1/tier-2)

#### Command
```bash
sed -n '1,200p' docs/operator/networking.md
```

#### Expected result
Replacement plan aligns with the tier policy and includes a cutover checklist.

#### Evidence outputs
None (policy reference).

#### Failure modes
- Tier-0 service replaced without MAC/DHCP determinism

#### Rollback / safe exit
Stop and document a deterministic replacement plan before proceeding.

### Task: Plan template upgrades (replace or blue/green only)

#### Intent
Avoid in-place upgrade assumptions when templates change.

#### Preconditions
- Template version change approved

#### Command
```bash
sed -n '1,200p' docs/images/template-upgrades.md
```

#### Expected result
Upgrade strategy is replace or blue/green; in-place upgrades are not used.

#### Evidence outputs
None (planning step).

#### Failure modes
- Assuming template changes update existing containers

#### Rollback / safe exit
Stop and re-scope the upgrade to a replace or blue/green cutover.

### Task: Terraform plan (read-only)

#### Intent
Compute planned infra changes for a specific environment.

#### Preconditions
- `ENV` selected
- Runner env configured

#### Command
```bash
make tf.plan ENV=samakia-prod
```

#### Expected result
Plan completes without prompts.

#### Evidence outputs
Plan output in terminal (or CI artifacts).

#### Failure modes
- Backend not reachable
- Missing env vars

#### Rollback / safe exit
Stop; do not apply.

---

## Drift & compliance

### Task: Drift packet generation (read-only)

#### Intent
Generate drift evidence packets without remediation.

#### Preconditions
- Backend reachable
- Runner env configured

#### Command
```bash
make audit.drift ENV=samakia-prod
```

#### Expected result
Drift packet generated under `evidence/`.

#### Evidence outputs
`evidence/drift/<env>/<UTC>/...`

#### Failure modes
- Backend unavailable
- Inventory resolution errors

#### Rollback / safe exit
Stop and remediate environment/credentials.

---

### Task: Tenant drift detection (read-only)

#### Intent
Detect tenant drift without remediation and write evidence packets.

#### Preconditions
- Tenant contracts present
- Drift tooling installed

#### Command
```bash
TENANT=all DRIFT_OFFLINE=1 DRIFT_NON_BLOCKING=1 DRIFT_FAIL_ON=none make drift.detect
```

#### Quick usage + guard vars
```bash
TENANT=all DRIFT_OFFLINE=1 DRIFT_NON_BLOCKING=1 DRIFT_FAIL_ON=none DRIFT_REQUIRE_SIGN=0 make drift.detect
# Guards: DRIFT_OFFLINE (offline-only), DRIFT_NON_BLOCKING (exit 0), DRIFT_FAIL_ON (none|warn|critical), DRIFT_REQUIRE_SIGN (0|1|auto)
```

#### Expected result
Drift evidence created per tenant; exit is non-blocking.

#### Evidence outputs
`evidence/drift/<tenant>/<UTC>/...`

#### Failure modes
- Missing tenant contracts
- Drift tooling not present

#### Rollback / safe exit
None required (read-only).

---

### Task: Tenant drift summary (read-only)

#### Intent
Emit tenant-visible drift summaries from the latest evidence.

#### Preconditions
- Drift detection run completed

#### Command
```bash
TENANT=all make drift.summary
```

#### Expected result
Tenant summaries written under `artifacts/tenant-status/`.

#### Evidence outputs
`artifacts/tenant-status/<tenant>/drift-summary.*`

#### Failure modes
- Missing drift evidence

#### Rollback / safe exit
None required (read-only).

---

### Task: Phase 12 Part 5 entry check (read-only)

#### Intent
Validate Phase 12 Part 5 prerequisites before acceptance.

#### Preconditions
- Drift tooling present
- No OPEN items in REQUIRED-FIXES.md

#### Command
```bash
make phase12.part5.entry.check
```

#### Expected result
Entry checklist written under `acceptance/`.

#### Evidence outputs
`acceptance/PHASE12_PART5_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing required markers
- Missing drift tooling

#### Rollback / safe exit
None required (read-only).

---

### Task: Phase 12 Part 5 acceptance (read-only)

#### Intent
Run drift detection and summary generation with evidence-only outputs.

#### Preconditions
- Phase 12 Part 5 entry check passes

#### Command
```bash
make phase12.part5.accept
```

#### Expected result
Drift evidence packets and tenant summaries created; acceptance marker written.

#### Evidence outputs
- `evidence/drift/<tenant>/<UTC>/...`
- `artifacts/tenant-status/<tenant>/drift-summary.*`
- `acceptance/PHASE12_PART5_ACCEPTED.md`

#### Failure modes
- Missing drift evidence inputs
- Policy gate failure

#### Rollback / safe exit
None required (read-only).

---

Phase 12 exposure one-pager: [phase12-exposure.md](phase12-exposure.md).

### Task: Phase 12 readiness packet (read-only)

#### Intent
Generate a deterministic Phase 12 release readiness packet (redacted).

#### Preconditions
- Phase 12 Parts 1–5 accepted
- No OPEN items in REQUIRED-FIXES.md

#### Command
```bash
TENANT=all make phase12.readiness.packet
```
Optional signing (prod): set `READINESS_SIGN=1` with a local GPG key. In CI, signing is skipped unless `READINESS_SIGN=1` is set.

#### Expected result
Readiness packet created under `evidence/release-readiness/phase12/<UTC>/`.

#### Evidence outputs
`evidence/release-readiness/phase12/<UTC>/...`

#### Failure modes
- Missing required markers
- Policy or docs gate failure

#### Rollback / safe exit
None required (read-only).

---

### Task: Phase 13 exposure plan (read-only)

#### Intent
Generate a governed exposure plan and evidence packet (no apply).

#### Preconditions
- Phase 12 acceptance marker present
- Phase 13 exposure policy validated

#### Command
```bash
ENV=samakia-dev TENANT=canary WORKLOAD=sample make exposure.plan
```

#### Expected result
Exposure plan evidence written under `evidence/exposure-plan/<tenant>/<workload>/<UTC>/`.

#### Evidence outputs
`evidence/exposure-plan/<tenant>/<workload>/<UTC>/plan.json`

#### Failure modes
- Policy denies scope (allowlist or prod signing/change window missing)
- Binding manifests not rendered

#### Rollback / safe exit
None required (read-only).

---

### Task: Phase 13 Part 1 entry check (read-only)

#### Intent
Validate exposure plan prerequisites before running acceptance.

#### Preconditions
- Phase 13 entry checklist present
- REQUIRED-FIXES.md has no OPEN items

#### Command
```bash
make phase13.part1.entry.check
```

#### Expected result
Checklist written under `acceptance/PHASE13_PART1_ENTRY_CHECKLIST.md`.

#### Evidence outputs
`acceptance/PHASE13_PART1_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing Phase 13 prerequisites or tooling
- Policy gate failure

#### Rollback / safe exit
None required (read-only).

---

### Task: Phase 13 Part 1 acceptance (read-only)

#### Intent
Run the Phase 13 Part 1 acceptance suite (plan-only).

#### Preconditions
- Phase 13 Part 1 entry check passes

#### Command
```bash
make phase13.part1.accept
```

#### Expected result
Acceptance marker written under `acceptance/PHASE13_PART1_ACCEPTED.md`.

#### Evidence outputs
`acceptance/PHASE13_PART1_ACCEPTED.md`

#### Failure modes
- Policy gate failure
- Exposure plan denied in non-prod
- Missing evidence/signing for prod plan (when required)

#### Rollback / safe exit
None required (read-only).

---

### Task: Expose canary workload (non-prod)

#### Intent
Run the full exposure choreography for a canary workload in non-prod.

#### Preconditions
- Phase 13 Part 1 accepted
- Approval author identified

#### Command
```bash
ENV=samakia-dev TENANT=canary WORKLOAD=sample make exposure.plan
PLAN_EVIDENCE_REF="evidence/exposure-plan/canary/sample/<UTC>" \
  APPROVER_ID="ops-001" EXPOSE_REASON="canary exposure" \
  TENANT=canary WORKLOAD=sample ENV=samakia-dev make exposure.approve
APPROVAL_DIR="evidence/exposure-approve/canary/sample/<UTC>" \
  EXPOSE_EXECUTE=1 EXPOSE_REASON="canary exposure" APPROVER_ID="ops-001" \
  TENANT=canary WORKLOAD=sample ENV=samakia-dev make exposure.apply
TENANT=canary WORKLOAD=sample ENV=samakia-dev make exposure.verify
ROLLBACK_EXECUTE=1 ROLLBACK_REASON="canary rollback" ROLLBACK_REQUESTED_BY="ops-001" \
  TENANT=canary WORKLOAD=sample ENV=samakia-dev make exposure.rollback
```

#### Expected result
Exposure artifacts created under `artifacts/exposure/` and evidence under `evidence/exposure-*`.

#### Evidence outputs
`evidence/exposure-plan/<tenant>/<workload>/<UTC>/...`
`evidence/exposure-approve/<tenant>/<workload>/<UTC>/...`
`evidence/exposure-apply/<tenant>/<workload>/<UTC>/...`
`evidence/exposure-verify/<tenant>/<workload>/<UTC>/...`
`evidence/exposure-rollback/<tenant>/<workload>/<UTC>/...`

#### Failure modes
- Missing approval or change window requirements
- Policy denies exposure scope

#### Rollback / safe exit
`ROLLBACK_EXECUTE=1 ROLLBACK_REASON="..." ROLLBACK_REQUESTED_BY="..." make exposure.rollback`

---

### Task: Expose prod workload (plan only unless window + signing)

#### Intent
Plan a prod exposure with required change window and signing gates.

#### Preconditions
- Prod allowlist exists in exposure policy
- Change window scheduled and signing key available

#### Command
```bash
EXPOSURE_SIGN=1 CHANGE_WINDOW_START="2026-01-02T01:00:00Z" CHANGE_WINDOW_END="2026-01-02T02:00:00Z" \
ENV=samakia-prod TENANT=canary WORKLOAD=sample make exposure.plan
```

#### Expected result
Plan evidence written under `evidence/exposure-plan/<tenant>/<workload>/<UTC>/`.

#### Evidence outputs
`evidence/exposure-plan/<tenant>/<workload>/<UTC>/...`

#### Failure modes
- Missing signing key or change window
- Policy denies prod scope

#### Rollback / safe exit
None required (plan-only).

---

### Task: Phase 13 Part 2 entry check (read-only)

#### Intent
Validate Part 2 prerequisites and tooling before acceptance.

#### Preconditions
- Phase 13 Part 1 acceptance present
- REQUIRED-FIXES.md has no OPEN items

#### Command
```bash
make phase13.part2.entry.check
```

#### Expected result
Checklist written under `acceptance/PHASE13_PART2_ENTRY_CHECKLIST.md`.

#### Evidence outputs
`acceptance/PHASE13_PART2_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing guards or tooling
- Policy/doc gates failing

#### Rollback / safe exit
None required (read-only).

---

### Task: Phase 13 Part 2 acceptance (read-only)

#### Intent
Run the Phase 13 Part 2 acceptance suite (dry-run only).

#### Preconditions
- Phase 13 Part 2 entry check passes

#### Command
```bash
CI=1 make phase13.part2.accept
```

#### Expected result
Acceptance markers written under `acceptance/PHASE13_PART2_ACCEPTED.md` and `acceptance/PHASE13_ACCEPTED.md`.

#### Evidence outputs
`acceptance/PHASE13_PART2_ACCEPTED.md`
`acceptance/PHASE13_ACCEPTED.md`

#### Failure modes
- Guarded apply/rollback invoked in CI
- Missing approval or plan evidence

#### Rollback / safe exit
None required (read-only).

---

### Task: Phase 13 acceptance (umbrella, read-only)

#### Intent
Run the Phase 13 umbrella acceptance (delegates to Part 2 acceptance).

#### Preconditions
- Phase 13 Part 2 entry check passes

#### Command
```bash
CI=1 make phase13.accept
```

#### Expected result
Acceptance markers written under `acceptance/PHASE13_PART2_ACCEPTED.md` and `acceptance/PHASE13_ACCEPTED.md`.

#### Evidence outputs
`acceptance/PHASE13_PART2_ACCEPTED.md`
`acceptance/PHASE13_ACCEPTED.md`

#### Failure modes
- Guarded apply/rollback invoked in CI
- Missing approval or plan evidence

#### Rollback / safe exit
None required (read-only).

---

### Task: Phase 12 Part 6 entry check (read-only)

#### Intent
Validate Phase 12 Part 6 prerequisites before acceptance.

#### Preconditions
- Phase 12 Parts 1–5 accepted
- Phase 11 hardening accepted
- No OPEN items in REQUIRED-FIXES.md

#### Command
```bash
make phase12.part6.entry.check
```

#### Expected result
Entry checklist written under `acceptance/`.

#### Evidence outputs
`acceptance/PHASE12_PART6_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing markers or scripts
- Policy gates not wired

#### Rollback / safe exit
None required (read-only).

---

### Task: Phase 12 acceptance (umbrella, read-only)

#### Intent
Run the Phase 12 read-only acceptance suite and generate the readiness packet.

#### Preconditions
- Phase 12 Parts 1–5 accepted
- Phase 12 Part 6 entry check passes

#### Command
```bash
TENANT=all make phase12.accept
```

#### Expected result
Readiness packet generated; no execute paths run.

#### Evidence outputs
`evidence/release-readiness/phase12/<UTC>/...`

#### Failure modes
- Policy/doc gates fail
- Offline verify or drift summary fails

#### Rollback / safe exit
None required (read-only).

---

### Task: Phase 12 Part 6 acceptance

#### Intent
Lock Phase 12 closure and create acceptance markers.

#### Preconditions
- Phase 12 acceptance passes
- No OPEN items in REQUIRED-FIXES.md

#### Command
```bash
make phase12.part6.accept
```

#### Expected result
Acceptance markers written for Part 6 and Phase 12.

#### Evidence outputs
- `acceptance/PHASE12_PART6_ACCEPTED.md`
- `acceptance/PHASE12_ACCEPTED.md`

#### Failure modes
- Readiness packet generation fails
- Policy or docs gate failure

#### Rollback / safe exit
None required; rerun after remediation.

---

## Milestone Phase 1–12 (end-to-end verification)

### Task: Milestone Phase 1–12 verification (read-only)

#### Intent
Run the full Phase 1–12 regression sweep and emit a consolidated evidence packet.

#### Preconditions
- Clean git working tree
- No OPEN items in REQUIRED-FIXES.md
- All phase acceptance markers present
- Runner access to required environments (DNS/MinIO/Shared/Prod)

#### Command
```bash
make milestone.phase1-12.verify
```

#### Expected result
Evidence packet created under `evidence/milestones/phase1-12/<UTC>/`.

#### Evidence outputs
`evidence/milestones/phase1-12/<UTC>/...`

#### Failure modes
- Missing acceptance markers or self-hash metadata
- Environment access or TLS guard failures
- Policy/validation regressions in any phase

#### Rollback / safe exit
None required (read-only).

---

### Task: Milestone Phase 1–12 lock

#### Intent
Create the milestone acceptance marker after verification passes.

#### Preconditions
- `make milestone.phase1-12.verify` PASS
- Roadmap/review/changelog updated to reflect milestone completion

#### Command
```bash
make milestone.phase1-12.lock
```

#### Expected result
Acceptance marker `acceptance/MILESTONE_PHASE1_12_ACCEPTED.md` created with self-hash.

#### Evidence outputs
`acceptance/MILESTONE_PHASE1_12_ACCEPTED.md`

#### Failure modes
- Verification did not PASS or evidence missing
- Commit mismatch between evidence and repo

#### Rollback / safe exit
None required; rerun after remediation.

---

## Alerting (routing defaults)

### Task: Validate drift alert routing defaults

#### Intent
Validate the routing defaults for drift alert evidence emission.

#### Preconditions
- Routing defaults present under `contracts/alerting/`

#### Command
```bash
make substrate.alert.validate
```

#### Expected result
Routing validation PASS with no external delivery enabled.

#### Evidence outputs
None (validation only).

#### Failure modes
- Missing tenant allowlist entry
- Delivery enabled by default

#### Rollback / safe exit
Stop and fix routing configuration.

### Task: Run routing defaults acceptance (evidence only)

#### Intent
Simulate WARN/FAIL drift events and verify evidence-only routing.

#### Preconditions
- Routing defaults validated

#### Command
```bash
make phase11.part5.routing.accept
```

#### Expected result
Evidence packets written under `evidence/alerts/` and no delivery attempted.

#### Evidence outputs
`evidence/alerts/<env>/<UTC>/...`

#### Failure modes
- Routing schema violation
- Tenant not allowlisted

#### Rollback / safe exit
Stop; do not enable external sinks.

---

## GameDays (dry-run vs execute)

### Task: GameDay dry-run (safe)

#### Intent
Run dry-run GameDay checks without mutation.

#### Preconditions
- Phase 3 entry READY

#### Command
```bash
make gameday.precheck
make gameday.evidence
make gameday.vip.failover.dry
make gameday.service.restart.dry
make gameday.postcheck
```

#### Expected result
All dry-run checks PASS; no service changes.

#### Evidence outputs
`artifacts/gameday/<id>/<UTC>/...`

#### Failure modes
- Precheck failures
- Missing allowlist

#### Rollback / safe exit
Stop; do not execute mutations.

---

## Consumers

### Task: Validate consumer contracts

#### Intent
Validate consumer manifests (schema + semantics + HA + disaster wiring).

#### Preconditions
- Consumer contracts present

#### Command
```bash
make consumers.validate
make consumers.ha.check
make consumers.disaster.check
make consumers.gameday.mapping.check
```

#### Expected result
All validations PASS.

#### Evidence outputs
None by default.

#### Failure modes
- Contract schema mismatch
- Missing disaster testcases

#### Rollback / safe exit
Stop and fix manifests.

### Task: Generate consumer readiness evidence and bundles

#### Intent
Produce readiness evidence packets and provisioning bundles (read-only).

#### Preconditions
- Consumer contracts valid

#### Command
```bash
make consumers.evidence
make consumers.bundle
make consumers.bundle.check
```

#### Expected result
Evidence and bundles generated under gitignored paths.

#### Evidence outputs
`evidence/consumers/...` and `artifacts/consumer-bundles/...`

#### Failure modes
- Bundle validation failures

#### Rollback / safe exit
Stop; fix bundle outputs.

---

## Tenant bindings (design validation)

### Task: Create a new tenant from templates

#### Intent
Scaffold a new tenant contract set from templates (design-only).

#### Preconditions
- Templates present under `contracts/tenants/_templates/`
- Choose a DNS-safe tenant id

#### Command
```bash
TENANT_ID="example-tenant"
DEST="contracts/tenants/examples/${TENANT_ID}"
mkdir -p "${DEST}"
cp -r contracts/tenants/_templates/* "${DEST}/"
```

#### Expected result
Tenant files copied to a new folder, ready for edits.

#### Evidence outputs
None.

#### Failure modes
- Missing templates
- Invalid tenant id format

#### Rollback / safe exit
Delete the new folder if created in error.

### Task: Validate tenant contracts

#### Intent
Validate tenant (project) bindings against schema and semantics.

#### Preconditions
- Tenant contracts present under `contracts/tenants/`

#### Command
```bash
make tenants.validate
make tenants.execute.policy.check
make tenants.dr.validate
```

#### Expected result
Schema and semantics checks PASS.

#### Evidence outputs
None by default.

#### Failure modes
- Schema mismatch
- Semantics violations (unknown consumers, missing quotas)

#### Rollback / safe exit
Stop and fix tenant contracts.

### Task: Inspect binding secret refs (read-only)

#### Intent
List binding secret references without reading secret values.

#### Preconditions
- Binding contracts exist under `contracts/bindings/`

#### Command
```bash
make bindings.secrets.inspect TENANT=all
```

#### Expected result
Secret refs listed; no secret values printed.

#### Evidence outputs
None (stdout only).

#### Failure modes
- Missing binding contracts
- Inline secret values detected

#### Rollback / safe exit
Stop; fix binding contracts.

### Task: Materialize binding secrets (dry-run)

#### Intent
Generate redacted evidence for secret materialization without writing secrets.

#### Preconditions
- `docs/bindings/secrets.md` reviewed
- Optional input file prepared

#### Command
```bash
make bindings.secrets.materialize.dryrun TENANT=all
```

#### Expected result
Redacted evidence written under `evidence/bindings/<tenant>/<UTC>/secrets/`.

#### Evidence outputs
`evidence/bindings/<tenant>/<UTC>/secrets/...`

#### Failure modes
- Missing `secret_ref` or `secret_shape`
- Unsupported backend

#### Rollback / safe exit
Stop; fix contracts or input map.

### Task: Materialize binding secrets (execute, guarded)

#### Intent
Write secrets to the offline file backend using operator-provided input.

#### Preconditions
- `BIND_SECRET_INPUT_FILE` prepared and validated
- Guard flags set

#### Command
```bash
MATERIALIZE_EXECUTE=1 \
BIND_SECRETS_BACKEND=file \
BIND_SECRET_INPUT_FILE=./secrets-input.json \
make bindings.secrets.materialize TENANT=project-birds
```

#### Expected result
Secrets written to the file backend; redacted evidence generated.

#### Evidence outputs
`evidence/bindings/<tenant>/<UTC>/secrets/...`

#### Failure modes
- Missing guard flags
- Input map missing required keys

#### Rollback / safe exit
Stop; do not reuse partially written secrets without review.

### Task: Plan binding secret rotation (read-only)

#### Intent
Compute rotation plans without writing new secrets.

#### Preconditions
- Rotation policy declared in bindings

#### Command
```bash
make bindings.secrets.rotate.plan TENANT=all
```

#### Expected result
Rotation plan evidence produced.

#### Evidence outputs
`evidence/bindings/<tenant>/<UTC>/rotation/plan.json`

#### Failure modes
- Invalid rotation policy

#### Rollback / safe exit
Stop; fix binding rotation policy.

### Task: Rotate binding secrets (dry-run)

#### Intent
Generate rotation evidence without writing secrets.

#### Preconditions
- Rotation plan is valid

#### Command
```bash
make bindings.secrets.rotate.dryrun TENANT=all
```

#### Expected result
Rotation evidence written; no secrets stored.

#### Evidence outputs
`evidence/bindings/<tenant>/<UTC>/rotation/...`

#### Failure modes
- Missing `secret_ref` or `secret_shape`

#### Rollback / safe exit
Stop; fix contracts.

### Task: Rotate binding secrets (execute, guarded)

#### Intent
Write a new secret version to the file backend and emit evidence.

#### Preconditions
- `ROTATE_INPUT_FILE` prepared or generation allowlisted
- Guard flags set

#### Command
```bash
ROTATE_EXECUTE=1 \
ROTATE_REASON="scheduled rotation" \
BIND_SECRETS_BACKEND=file \
ROTATE_INPUT_FILE=./rotation-input.json \
make bindings.secrets.rotate TENANT=project-birds
```

#### Expected result
New secret version written; evidence generated.

#### Evidence outputs
`evidence/bindings/<tenant>/<UTC>/rotation/...`

#### Failure modes
- Missing guard flags
- Input map missing required entries

#### Rollback / safe exit
Stop; do not cut over workloads in Phase 12 Part 2.

### Task: Define tenant capacity (capacity.yml)

#### Intent
Declare tenant-level capacity/quotas for substrate consumers.

#### Preconditions
- Tenant folder exists under `contracts/tenants/`
- Templates available under `contracts/tenants/_templates/`

#### Command
```bash
TENANT_ID="example-tenant"
cp contracts/tenants/_templates/capacity.yml "contracts/tenants/${TENANT_ID}/capacity.yml"
```

#### Expected result
`capacity.yml` exists for the tenant and is ready to edit.

#### Evidence outputs
None.

#### Failure modes
- Missing template
- Tenant folder not found

#### Rollback / safe exit
Remove the file and re-copy if needed.

### Task: Validate capacity + SLO semantics

#### Intent
Ensure capacity and SLO/failure semantics are declared and enforceable.

#### Preconditions
- Tenant `capacity.yml` present
- Enabled contracts include SLO/failure semantics

#### Command
```bash
make tenants.capacity.validate TENANT=all
make substrate.contracts.validate
```

#### Expected result
Capacity and enabled contracts validate cleanly.

#### Evidence outputs
None by default.

#### Failure modes
- Missing capacity.yml
- SLO/failure semantics missing in enabled.yml

#### Rollback / safe exit
Fix the contracts and re-run.

### Task: Run capacity guard (contract-only)

#### Intent
Evaluate declared consumption vs capacity limits before apply/DR execute.

#### Preconditions
- Tenant capacity files validated

#### Command
```bash
make substrate.capacity.guard TENANT=all
```

#### Expected result
Capacity guard PASS or WARN; FAIL blocks apply/DR execute.

#### Evidence outputs
None unless `substrate.capacity.evidence` is used.

#### Failure modes
- Limits exceeded (deny_on_exceed)
- Missing capacity.yml

#### Rollback / safe exit
Adjust capacity or resources; re-run guard.

### Task: Generate capacity evidence (read-only)

#### Intent
Write deterministic capacity evidence packets for auditability.

#### Preconditions
- Capacity guard passes or is warning-only

#### Command
```bash
make substrate.capacity.evidence TENANT=all
```

#### Expected result
Evidence written under `evidence/tenants/<tenant>/<UTC>/substrate-capacity/`.

#### Evidence outputs
`evidence/tenants/<tenant>/<UTC>/substrate-capacity/...`

#### Failure modes
- Missing capacity.yml
- Schema/semantics errors

#### Rollback / safe exit
Fix contracts; re-run.

### Task: Validate substrate enabled contracts (design-only)

#### Intent
Validate enabled bindings for substrate executors (design-only; no execution).

#### Preconditions
- Enabled bindings present under `contracts/tenants/**/consumers/*/enabled.yml`

#### Command
```bash
make substrate.contracts.validate
```

#### Expected result
Substrate contract validation PASS.

#### Evidence outputs
None by default.

#### Failure modes
- Provider/consumer mismatch
- DR testcase mismatch

#### Rollback / safe exit
Stop and fix enabled contracts.

### Task: Generate tenant substrate plan (read-only)

#### Intent
Produce deterministic, non-executing substrate plans for tenant enabled bindings.

#### Preconditions
- Enabled bindings present under `contracts/tenants/**/consumers/*/enabled.yml`

#### Command
```bash
make substrate.plan TENANT=all
```

#### Expected result
Plan evidence generated; unreachable endpoints marked as `unknown`.

#### Evidence outputs
`evidence/tenants/<tenant-id>/<UTC>/substrate-plan/...`

#### Failure modes
- Invalid enabled bindings
- Missing DR taxonomy

#### Rollback / safe exit
Stop and fix contracts; re-run plan.

### Task: Observe substrate runtime (read-only)

#### Intent
Collect read-only runtime observations and generate evidence packets.

#### Preconditions
- Enabled bindings present under `contracts/tenants/**/consumers/*/enabled.yml`

#### Command
```bash
make substrate.observe TENANT=all
```

#### Expected result
Observation evidence generated; reachability marked `unknown` when endpoints are unreachable or CI-safe checks are enforced.

#### Evidence outputs
`evidence/tenants/<tenant-id>/<UTC>/substrate-observe/observed.json`

#### Failure modes
- Invalid enabled bindings
- Missing tooling (bash, jq, python3)

#### Rollback / safe exit
None required (read-only).

### Task: Compare declared vs observed drift (read-only)

#### Intent
Classify drift between declared contracts and observed runtime state.

#### Preconditions
- Substrate observability tooling present
- Capacity contracts validated (if present)

#### Command
```bash
make substrate.observe.compare TENANT=all
```

#### Expected result
Drift classification emitted as `PASS`, `WARN`, or `FAIL`. No auto-remediation occurs.

#### Evidence outputs
`evidence/tenants/<tenant-id>/<UTC>/substrate-observe/decision.json`

#### Failure modes
- Schema/engine errors
- Missing contracts or capacity files

#### Rollback / safe exit
None required (read-only).

### Task: Generate substrate observation evidence (read-only)

#### Intent
Produce deterministic observation evidence packets without mutation.

#### Preconditions
- Substrate observe tooling present
- Enabled bindings present

#### Command
```bash
make substrate.observe.evidence TENANT=all
```

#### Expected result
Observation evidence written under `evidence/tenants/<tenant>/<UTC>/substrate-observe/`.

#### Evidence outputs
`evidence/tenants/<tenant>/<UTC>/substrate-observe/observed.json`

#### Failure modes
- Invalid enabled bindings
- Missing tooling (bash, jq, python3)

#### Rollback / safe exit
None required (read-only).

### Task: Run Phase 11 hardening entry check (read-only)

#### Intent
Generate the pre-exposure hardening entry checklist before allowing Phase 12 exposure.

#### Preconditions
- Phase 11 Part 5 acceptance marker present
- REQUIRED-FIXES.md has no OPEN items

#### Command
```bash
make phase11.hardening.entry.check
```

#### Expected result
Checklist rendered to `acceptance/PHASE11_HARDENING_ENTRY_CHECKLIST.md` and `docs/operator/hardening.md`.

#### Evidence outputs
- `acceptance/PHASE11_HARDENING_ENTRY_CHECKLIST.md`
- `docs/operator/hardening.md`

#### Failure modes
- Missing Phase 11 acceptance markers
- Hardening prerequisites missing (capacity guard/observe tooling)
- Phase 12 artifacts detected

#### Rollback / safe exit
None required (read-only).

### Task: Run Phase 11 hardening gate acceptance (read-only)

#### Intent
Run the full pre-exposure hardening gate and emit the acceptance marker.

#### Preconditions
- Entry checklist passes (`make phase11.hardening.entry.check`)

#### Command
```bash
make phase11.hardening.accept
```

#### Expected result
Acceptance marker and evidence packet written; Phase 12 exposure may proceed.

#### Evidence outputs
- `acceptance/PHASE11_HARDENING_JSON_ACCEPTED.md`
- `evidence/hardening/<UTC>/summary.md`

#### Failure modes
- Lint/validate/policy failures
- Observability compare failures
- OPEN items in REQUIRED-FIXES.md

#### Rollback / safe exit
None required (read-only).

### Task: Run Phase 11 Part 4 entry check (read-only)

#### Intent
Verify Part 4 readiness before running its acceptance gate.

#### Preconditions
- Phase 11 Part 3 accepted
- REQUIRED-FIXES.md has no OPEN items

#### Command
```bash
make phase11.part4.entry.check
```

#### Expected result
Entry checklist written under `acceptance/PHASE11_PART4_ENTRY_CHECKLIST.md`.

#### Evidence outputs
`acceptance/PHASE11_PART4_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing Part 4 prerequisites
- OPEN items in REQUIRED-FIXES.md

#### Rollback / safe exit
None required (read-only).

### Task: Run Phase 11 Part 4 acceptance (read-only)

#### Intent
Run Part 4 acceptance gates and emit the acceptance marker.

#### Preconditions
- Part 4 entry checklist passes

#### Command
```bash
make phase11.part4.accept
```

#### Expected result
Acceptance marker written; no infra mutation occurs.

#### Evidence outputs
`acceptance/PHASE11_PART4_ACCEPTED.md`

#### Failure modes
- Policy/validation failures
- Missing prerequisite artifacts

#### Rollback / safe exit
None required (read-only).

### Task: Run Phase 11 Part 5 entry check (read-only)

#### Intent
Verify Part 5 prerequisites before running routing defaults acceptance.

#### Preconditions
- Phase 11 Part 4 accepted
- REQUIRED-FIXES.md has no OPEN items

#### Command
```bash
make phase11.part5.entry.check
```

#### Expected result
Entry checklist written under `acceptance/PHASE11_PART5_ENTRY_CHECKLIST.md`.

#### Evidence outputs
`acceptance/PHASE11_PART5_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing Part 5 prerequisites
- OPEN items in REQUIRED-FIXES.md

#### Rollback / safe exit
None required (read-only).

### Task: Verify tenant substrate endpoints (read-only)

#### Intent
Check endpoint reachability for enabled contracts without executing mutations.

#### Preconditions
- Enabled bindings present under `contracts/tenants/**/consumers/*/enabled.yml`

#### Command
```bash
make substrate.verify TENANT=all
```

#### Expected result
Verification evidence generated; unreachable endpoints are marked `unknown`.

#### Evidence outputs
`evidence/tenants/<tenant-id>/<UTC>/substrate-verify/...`

#### Failure modes
- Invalid enabled bindings
- Missing tooling (bash, jq, python3)

#### Rollback / safe exit
None required (read-only).

### Task: Diagnose substrate executor prerequisites (read-only)

#### Intent
Confirm the substrate executor runtime can plan and dry-run without infra access.

#### Preconditions
- Phase 11 design accepted
- Substrate contracts validated

#### Command
```bash
make substrate.doctor
```

#### Expected result
Doctor checks pass and report required tools/contracts present.

#### Evidence outputs
None (stdout only)

#### Failure modes
- Missing tooling (bash, jq, python3)
- Missing substrate contracts

#### Rollback / safe exit
None required (read-only)

### Task: Run tenant substrate DR dry-run (read-only)

#### Intent
Generate DR dry-run evidence mapped to the substrate DR taxonomy.

#### Preconditions
- Enabled bindings include `dr.required_testcases`

#### Command
```bash
make substrate.dr.dryrun TENANT=all
```

#### Expected result
DR dry-run evidence generated; no snapshots or restores executed.

#### Evidence outputs
`evidence/tenants/<tenant-id>/<UTC>/substrate-dr-dryrun/...`

#### Failure modes
- Missing DR placeholders
- Unknown DR testcases

#### Rollback / safe exit
Stop and fix DR requirements; re-run dry-run.

### Task: Apply tenant substrate enablement (guarded)

#### Intent
Execute tenant substrate enablement for enabled contracts with explicit guards and evidence.

#### Preconditions
- Enabled contracts are valid (`make substrate.contracts.validate`).
- Secrets resolved via `secret_ref` are available locally (offline-first secrets).
- Execute policy allowlists include the tenant/env/provider.
- Capacity guard passes (`make substrate.capacity.guard`).

#### Command
```bash
TENANT_EXECUTE=1 I_UNDERSTAND_TENANT_MUTATION=1 EXECUTE_REASON="initial enablement" \
ENV=samakia-dev TENANT=all \
make substrate.apply
```

#### Expected result
Apply executes idempotently and writes evidence under `substrate-apply/`.

#### Evidence outputs
`evidence/tenants/<tenant-id>/<UTC>/substrate-apply/...`

#### Failure modes
- Execute policy deny (env/tenant/provider not allowlisted)
- Missing secrets for `secret_ref`
- Idempotency error or connectivity failure

#### Rollback / safe exit
Stop and fix policy or secrets; re-run apply.

### Task: Run tenant substrate DR execute (guarded)

#### Intent
Run backup + restore verification for enabled contracts with explicit guards.

#### Preconditions
- DR testcases declared in enabled contracts.
- Execute policy allows DR execution.
- Change window + signing required for prod.

#### Command
```bash
TENANT_EXECUTE=1 I_UNDERSTAND_TENANT_MUTATION=1 EXECUTE_REASON="dr verification" \
DR_EXECUTE=1 ENV=samakia-dev TENANT=all \
make substrate.dr.execute
```

#### Expected result
DR execute runs backups and restore verification with evidence under `substrate-dr-execute/`.

#### Evidence outputs
`evidence/tenants/<tenant-id>/<UTC>/substrate-dr-execute/...`

#### Failure modes
- DR execute guard missing
- Change window/signing missing for prod
- Provider-specific backup/restore failure

#### Rollback / safe exit
Stop execution; resolve provider-specific issues before re-run.

### Task: Tenant tooling doctor

#### Intent
Confirm tenant tooling and contract directories exist.

#### Preconditions
- Tenant tooling scripts present under `ops/tenants/`

#### Command
```bash
make tenants.doctor
```

#### Expected result
`PASS: tenant tooling present`.

#### Evidence outputs
None.

#### Failure modes
- Missing tenant schemas or templates
- Missing validation scripts

#### Rollback / safe exit
Stop and restore missing files.

### Task: Generate tenant evidence packet

#### Intent
Generate redacted, deterministic evidence for tenant contracts.

#### Preconditions
- Tenant contracts valid

#### Command
```bash
TENANT=all make tenants.evidence
```

#### Expected result
Evidence packets created under `evidence/tenants/...`.

#### Evidence outputs
`evidence/tenants/<tenant-id>/<UTC>/...`

#### Failure modes
- Validation failures
- Secret-like values detected

#### Rollback / safe exit
Fix contracts and re-run evidence.

---

## Tenant bindings (Phase 12)

### Task: Create a binding from template

#### Intent
Define how a workload consumes substrate endpoints (read-only contract).

#### Preconditions
- Tenant contract exists
- Binding template present under `contracts/bindings/_templates/`

#### Command
```bash
TENANT_ID="project-birds"
WORKLOAD_ID="birds-api"
DEST="contracts/bindings/tenants/${TENANT_ID}"
mkdir -p "${DEST}"
cp contracts/bindings/_templates/binding.yml "${DEST}/${WORKLOAD_ID}.binding.yml"
```

#### Expected result
Binding file created and ready to edit.

#### Evidence outputs
None.

#### Failure modes
- Missing binding template
- Invalid tenant id

#### Rollback / safe exit
Remove the binding file if created in error.

### Task: Validate bindings

#### Intent
Validate binding schema, semantics, and safety (capacity guard included).

#### Preconditions
- Binding contracts present under `contracts/bindings/tenants/`

#### Command
```bash
make bindings.validate TENANT=all
```

#### Expected result
Binding checks PASS.

#### Evidence outputs
None by default.

#### Failure modes
- Schema mismatch
- Invalid tenant references
- Capacity guard failure

#### Rollback / safe exit
Fix binding files and re-run validation.

### Task: Render connection manifests (read-only)

#### Intent
Generate redacted connection manifests for workloads (no secrets).

#### Preconditions
- Binding contracts valid

#### Command
```bash
make bindings.render TENANT=all
```

#### Expected result
Connection manifests written under `artifacts/bindings/...`.

#### Evidence outputs
`artifacts/bindings/<tenant>/<workload>/...`

#### Failure modes
- Missing referenced enabled contract
- Invalid endpoint shape

#### Rollback / safe exit
Fix binding or enabled contract and re-run render.

### Task: Verify bindings connectivity (offline)

#### Intent
Validate workload-side connectivity using rendered manifests (no secrets, read-only).

#### Preconditions
- Binding manifests rendered under `artifacts/bindings/`

#### Command
```bash
make bindings.verify.offline TENANT=all
```

#### Expected result
Verification PASS with evidence under `evidence/bindings-verify/`.

#### Evidence outputs
`evidence/bindings-verify/<tenant>/<UTC>/...`

#### Failure modes
- Missing connection manifests
- Invalid binding shape

#### Rollback / safe exit
Fix bindings or re-run render; no mutation occurs.

### Task: Verify bindings connectivity (live, guarded)

#### Intent
Validate workload-side connectivity with secret resolution (read-only, guarded).

#### Preconditions
- Secrets backend configured
- Not running in CI
- Explicit live-mode guard set

#### Command
```bash
VERIFY_MODE=live VERIFY_LIVE=1 \
make bindings.verify.live TENANT=project-birds
```

#### Expected result
Verification PASS and evidence written under `evidence/bindings-verify/`.

#### Evidence outputs
`evidence/bindings-verify/<tenant>/<UTC>/...`

#### Failure modes
- Missing secret_ref
- Live guard not set

#### Rollback / safe exit
Stop and fix secret backend or binding inputs; no mutation occurs.

### Task: Apply binding (guarded, non-prod)

#### Intent
Approve and write manifests to the approved artifacts location.

#### Preconditions
- Binding validated
- Non-prod environment

#### Command
```bash
BIND_EXECUTE=1 \
make bindings.apply TENANT=project-birds WORKLOAD=birds-api
```

#### Expected result
Evidence packet created and manifests written under `artifacts/bindings/...`.

#### Evidence outputs
`evidence/bindings/<tenant>/<UTC>/...`

#### Failure modes
- Missing `BIND_EXECUTE=1`
- Prod binding without approval

#### Rollback / safe exit
Stop; do not propagate manifests to downstream systems.

---

## Tenant proposals (Phase 12 Part 4)

### Quick CLI + guard flags (summary)

```bash
# Intake (read-only)
make proposals.submit FILE=examples/proposals/add-postgres-binding.yml
make proposals.validate PROPOSAL_ID=add-postgres-binding
make proposals.review PROPOSAL_ID=add-postgres-binding

# Decision (guarded)
OPERATOR_APPROVE=1 APPROVER_ID="ops-01" make proposals.approve PROPOSAL_ID=add-postgres-binding
OPERATOR_REJECT=1  APPROVER_ID="ops-01" make proposals.reject  PROPOSAL_ID=add-postgres-binding

# Apply
APPLY_DRYRUN=1 make proposals.apply PROPOSAL_ID=add-postgres-binding
PROPOSAL_APPLY=1 BIND_EXECUTE=1 make proposals.apply PROPOSAL_ID=add-postgres-binding
```

### Task: Submit a proposal (read-only intake)

#### Intent
Submit a tenant proposal for binding or capacity changes (no apply).

#### Preconditions
- Proposal YAML prepared
- No secrets in proposal

#### Command
```bash
make proposals.submit FILE=examples/proposals/add-postgres-binding.yml
```

#### Expected result
Proposal stored under `proposals/inbox/<tenant>/<proposal_id>/proposal.yml`.

#### Evidence outputs
Proposal file in `proposals/inbox/...` (gitignored).

#### Failure modes
- Missing proposal schema
- Proposal contains secret-like values

#### Rollback / safe exit
Remove the inbox entry if submitted in error.

### Task: Validate a proposal

#### Intent
Validate a proposal against schema, bindings, and capacity rules.

#### Preconditions
- Proposal submitted or example exists

#### Command
```bash
make proposals.validate PROPOSAL_ID=add-postgres-binding
```

#### Expected result
Validation PASS (no changes applied).

#### Evidence outputs
None by default (use `VALIDATION_OUT=...` for JSON).

#### Failure modes
- Schema mismatch
- Target not found under tenant

#### Rollback / safe exit
Fix proposal and re-run validation.

### Task: Review a proposal (diff + impact)

#### Intent
Generate review bundle for operator decision.

#### Preconditions
- Proposal validates

#### Command
```bash
make proposals.review PROPOSAL_ID=add-postgres-binding
```

#### Expected result
Review bundle under `evidence/proposals/<tenant>/<proposal_id>/`.

#### Evidence outputs
`evidence/proposals/<tenant>/<proposal_id>/diff.md`, `impact.json`, `validation.json`

#### Failure modes
- Invalid target path
- Missing tenant binding contract

#### Rollback / safe exit
Fix proposal inputs and re-run review.

### Task: Approve a proposal (guarded)

#### Intent
Record an explicit operator approval (signed in prod).

#### Preconditions
- Proposal reviewed
- Operator identity available

#### Command
```bash
OPERATOR_APPROVE=1 APPROVER_ID="ops-01" \
make proposals.approve PROPOSAL_ID=add-postgres-binding
```

#### Expected result
Decision recorded under `evidence/proposals/<tenant>/<proposal_id>/decision.json`.

#### Evidence outputs
`evidence/proposals/<tenant>/<proposal_id>/decision.json` (+ signature in prod)

#### Failure modes
- Missing OPERATOR_APPROVE
- Prod approval without signing key

#### Rollback / safe exit
Reject the proposal if approval was accidental.

### Task: Reject a proposal (guarded)

#### Intent
Record rejection and archive the proposal.

#### Preconditions
- Operator identity available

#### Command
```bash
OPERATOR_REJECT=1 APPROVER_ID="ops-01" \
make proposals.reject PROPOSAL_ID=add-postgres-binding
```

#### Expected result
Decision recorded and proposal archived under `proposals/archive/...`.

#### Evidence outputs
`evidence/proposals/<tenant>/<proposal_id>/decision.json`

#### Failure modes
- Missing OPERATOR_REJECT
- Proposal not found in inbox

#### Rollback / safe exit
None; rejection is immutable.

### Task: Apply proposal (dry-run)

#### Intent
Preview operator apply path with no mutation.

#### Preconditions
- Proposal approved

#### Command
```bash
APPLY_DRYRUN=1 \
make proposals.apply PROPOSAL_ID=add-postgres-binding
```

#### Expected result
Dry-run output lists planned binding apply steps.

#### Evidence outputs
None (dry-run output only).

#### Failure modes
- Missing approval decision
- Prod decision missing signature

#### Rollback / safe exit
Stop; fix approval or proposal inputs.

### Task: Apply proposal (execute, guarded)

#### Intent
Run operator-controlled apply using existing binding apply paths.

#### Preconditions
- Proposal approved
- Non-prod environment (prod requires signed decision)
- Binding apply guards satisfied

#### Command
```bash
PROPOSAL_APPLY=1 BIND_EXECUTE=1 \
make proposals.apply PROPOSAL_ID=add-postgres-binding
```

#### Expected result
Bindings applied via operator-controlled paths (no tenant self-apply).

#### Evidence outputs
Binding apply evidence under `evidence/bindings/...`.

#### Failure modes
- Missing PROPOSAL_APPLY guard
- Prod decision signature missing

#### Rollback / safe exit
Stop; do not proceed without proper guards.

### Task: Phase 12 Part 4 entry check

#### Intent
Verify Phase 12 Part 4 prerequisites before acceptance (read-only).

#### Preconditions
- Phase 12 Part 3 accepted
- Proposal tooling present

#### Command
```bash
make phase12.part4.entry.check
```

#### Expected result
Entry checklist PASS with no blockers.

#### Evidence outputs
`acceptance/PHASE12_PART4_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing proposal tooling
- OPEN items in REQUIRED-FIXES.md

#### Rollback / safe exit
Stop and remediate reported blockers before acceptance.

### Task: Phase 12 Part 4 acceptance

#### Intent
Run Phase 12 Part 4 acceptance gates (read-only).

#### Preconditions
- Phase 12 Part 4 entry check PASS
- No OPEN items in REQUIRED-FIXES.md

#### Command
```bash
make phase12.part4.accept
```

#### Expected result
Acceptance PASS and marker written.

#### Evidence outputs
`acceptance/PHASE12_PART4_ACCEPTED.md`

#### Failure modes
- Proposal validation or review fails
- Policy gate failure

#### Rollback / safe exit
Stop; do not claim acceptance until gates PASS.

### Task: Phase 12 Part 3 entry check

#### Intent
Verify Phase 12 Part 3 prerequisites before acceptance (read-only).

#### Preconditions
- Phase 12 Part 2 accepted
- Repo is clean

#### Command
```bash
make phase12.part3.entry.check
```

#### Expected result
Entry checklist PASS with no blockers.

#### Evidence outputs
`acceptance/PHASE12_PART3_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing Phase 12 Part 3 prerequisites
- OPEN items in REQUIRED-FIXES.md

#### Rollback / safe exit
Stop and remediate the reported blockers before acceptance.

### Task: Phase 12 Part 3 acceptance

#### Intent
Run Phase 12 Part 3 acceptance gates (read-only).

#### Preconditions
- Phase 12 Part 3 entry check PASS
- No OPEN items in REQUIRED-FIXES.md

#### Command
```bash
make phase12.part3.accept
```

#### Expected result
Acceptance PASS and marker written.

#### Evidence outputs
`acceptance/PHASE12_PART3_ACCEPTED.md`

#### Failure modes
- Validation or policy gate failure

#### Rollback / safe exit
Stop; do not claim acceptance until gates PASS.

### Task: Phase 12 Part 1 entry check

#### Intent
Verify Phase 12 Part 1 prerequisites before acceptance (read-only).

#### Preconditions
- Phase 12 Part 1 prerequisites exist
- Repo is clean

#### Command
```bash
make phase12.part1.entry.check
```

#### Expected result
Entry checklist PASS with no blockers.

#### Evidence outputs
None (checklist only).

#### Failure modes
- Missing Phase 12 prerequisites
- OPEN items in REQUIRED-FIXES.md

#### Rollback / safe exit
Stop and remediate the reported blockers before acceptance.

### Task: Phase 12 Part 1 acceptance

#### Intent
Run Phase 12 Part 1 acceptance gates (read-only).

#### Preconditions
- Phase 12 Part 1 entry check PASS
- No OPEN items in REQUIRED-FIXES.md

#### Command
```bash
make phase12.part1.accept
```

#### Expected result
Acceptance PASS and marker written.

#### Evidence outputs
`acceptance/PHASE12_PART1_ACCEPTED.md`

#### Failure modes
- Validation or policy gate failure

#### Rollback / safe exit
Stop; do not claim acceptance until gates PASS.

### Task: Phase 12 Part 2 entry check

#### Intent
Verify Phase 12 Part 2 prerequisites before acceptance (read-only).

#### Preconditions
- Phase 12 Part 2 prerequisites exist
- Repo is clean

#### Command
```bash
make phase12.part2.entry.check
```

#### Expected result
Entry checklist PASS with no blockers.

#### Evidence outputs
None (checklist only).

#### Failure modes
- Missing Phase 12 prerequisites
- OPEN items in REQUIRED-FIXES.md

#### Rollback / safe exit
Stop and remediate the reported blockers before acceptance.

### Task: Phase 12 Part 2 acceptance

#### Intent
Run Phase 12 Part 2 acceptance gates (read-only).

#### Preconditions
- Phase 12 Part 2 entry check PASS
- No OPEN items in REQUIRED-FIXES.md

#### Command
```bash
make phase12.part2.accept
```

#### Expected result
Acceptance PASS and marker written.

#### Evidence outputs
`acceptance/PHASE12_PART2_ACCEPTED.md`

#### Failure modes
- Validation or policy gate failure

#### Rollback / safe exit
Stop; do not claim acceptance until gates PASS.

### Task: Issue tenant credentials (offline-first)

#### Intent
Create tenant credentials in an encrypted local store (no secrets in Git).

#### Preconditions
- Tenant endpoints declared
- Passphrase set (`TENANT_CREDS_PASSPHRASE` or file)

#### Command
```bash
TENANT_CREDS_ISSUE=1 \
TENANT_CREDS_PASSPHRASE="change-me" \
make tenants.creds.issue TENANT=project-birds CONSUMER=database ENDPOINT_REF=db-primary
```

#### Expected result
Encrypted credentials stored under `~/.config/samakia-fabric/tenants/<tenant>/`.

#### Evidence outputs
`evidence/tenants/<tenant>/<UTC>/creds/...`

#### Failure modes
- Missing passphrase
- Endpoint reference not found

#### Rollback / safe exit
Do not commit any generated evidence; remove local secrets if created in error.

### Task: Plan tenant enablement (dry-run)

#### Intent
Validate enabled bindings and show the execute plan without mutation.

#### Preconditions
- Enabled bindings present (`consumers/<type>/enabled.yml`)
- Execute policy allowlists tenant and env

#### Command
```bash
ENV=samakia-dev EXECUTE_REASON="plan-only" \
make tenants.plan TENANT=project-birds
```

#### Expected result
Plan output lists enabled bindings and modes.

#### Evidence outputs
None by default.

#### Failure modes
- Tenant or env not allowlisted
- Enabled bindings invalid

#### Rollback / safe exit
Fix bindings or policy allowlist; re-run plan.

### Task: Apply tenant enablement (guarded)

#### Intent
Execute tenant enablement in a guarded, auditable way.

#### Preconditions
- Plan passes
- Execute policy allowlists tenant and env
- Explicit guards set
- Prod requires change window + evidence signing

#### Command
```bash
ENV=samakia-dev \
TENANT_EXECUTE=1 I_UNDERSTAND_TENANT_MUTATION=1 \
EXECUTE_REASON="enable tenant bindings" \
make tenants.apply TENANT=project-birds
```

#### Expected result
Credentials issued for bindings with `mode=execute`; evidence recorded.

#### Evidence outputs
`evidence/tenants/<tenant>/<UTC>/execute/...`

#### Failure modes
- Missing guards
- Policy disallows env/tenant

#### Rollback / safe exit
Stop and remove local credentials if needed.

### Task: Tenant DR dry-run

#### Intent
Validate DR testcases and readiness without mutation.

#### Preconditions
- Enabled bindings with DR expectations

#### Command
```bash
ENV=samakia-dev make tenants.dr.run TENANT=project-birds
```

#### Expected result
DR readiness evidence recorded (dry-run).

#### Evidence outputs
`evidence/tenants/<tenant>/<UTC>/dr/...`

#### Failure modes
- Missing DR testcases

#### Rollback / safe exit
Fix DR mappings and re-run.

### Task: Tenant DR execute (guarded)

#### Intent
Run guarded DR execution for a tenant (optional, non-default).

#### Preconditions
- Execute policy allows tenant/env
- DR execute guards set
- Prod requires change window + evidence signing

#### Command
```bash
ENV=samakia-dev DR_EXECUTE=1 \
TENANT_EXECUTE=1 I_UNDERSTAND_TENANT_MUTATION=1 \
EXECUTE_REASON="tenant DR execute" \
make tenants.dr.run TENANT=project-birds DR_MODE=execute
```

#### Expected result
DR execution evidence recorded with guards.

#### Evidence outputs
`evidence/tenants/<tenant>/<UTC>/dr/...`

#### Failure modes
- Missing guards or change window (prod)

#### Rollback / safe exit
Stop and review evidence before any further action.

### Task: Phase 10 Part 1 entry checklist

#### Intent
Confirm Phase 10 Part 1 prerequisites are satisfied before acceptance.

#### Preconditions
- Phase 9 accepted marker present
- Tenant contracts and docs present

#### Command
```bash
make phase10.part1.entry.check
```

#### Expected result
Checklist written under `acceptance/PHASE10_PART1_ENTRY_CHECKLIST.md`.

#### Evidence outputs
`acceptance/PHASE10_PART1_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing ADR-0027
- Missing tenant contracts or tools

#### Rollback / safe exit
Stop and restore missing files.

### Task: Phase 10 Part 1 acceptance (read-only)

#### Intent
Run the Phase 10 Part 1 acceptance suite (non-destructive).

#### Preconditions
- Phase 10 Part 1 entry checklist passes
- Tenant contracts valid

#### Command
```bash
make phase10.part1.accept
```

#### Expected result
Acceptance marker written under `acceptance/PHASE10_PART1_ACCEPTED.md`.

#### Evidence outputs
`acceptance/PHASE10_PART1_ACCEPTED.md`

#### Failure modes
- Validation errors
- Evidence generation errors

#### Rollback / safe exit
Stop and remediate validation issues.

### Task: Phase 10 Part 2 entry checklist

#### Intent
Confirm Phase 10 Part 2 prerequisites are satisfied before acceptance.

#### Preconditions
- Phase 10 Part 1 accepted marker present
- Tenant execute policy and tooling present

#### Command
```bash
make phase10.part2.entry.check
```

#### Expected result
Checklist written under `acceptance/PHASE10_PART2_ENTRY_CHECKLIST.md`.

#### Evidence outputs
`acceptance/PHASE10_PART2_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing ADR-0028
- Missing execute-policy or DR harness

#### Rollback / safe exit
Stop and restore missing artifacts.

### Task: Phase 10 Part 2 acceptance (read-only)

#### Intent
Run the Phase 10 Part 2 acceptance suite (non-destructive).

#### Preconditions
- Phase 10 Part 2 entry checklist passes
- Tenant execute policy validated

#### Command
```bash
make phase10.part2.accept
```

#### Expected result
Acceptance marker written under `acceptance/PHASE10_PART2_ACCEPTED.md`.

#### Evidence outputs
`acceptance/PHASE10_PART2_ACCEPTED.md`

#### Failure modes
- Execute policy validation fails
- DR harness validation fails

#### Rollback / safe exit
Stop and remediate validation issues.

### Task: Phase 10 entry checklist (design-only)

#### Intent
Confirm Phase 10 design entry conditions are satisfied.

#### Preconditions
- Prior phase acceptance markers present

#### Command
```bash
make phase10.entry.check
```

#### Expected result
Checklist written under `acceptance/PHASE10_ENTRY_CHECKLIST.md`.

#### Evidence outputs
`acceptance/PHASE10_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing contracts or schemas
- Docs/CI gates not wired

#### Rollback / safe exit
Stop and remediate missing artifacts.

### Task: Phase 11 entry checklist (design-only)

#### Intent
Confirm Phase 11 design entry conditions are satisfied.

#### Preconditions
- Phase 10 Part 2 accepted marker present
- Substrate contracts and validation tooling present

#### Command
```bash
make phase11.entry.check
```

#### Expected result
Checklist written under `acceptance/PHASE11_ENTRY_CHECKLIST.md`.

#### Evidence outputs
`acceptance/PHASE11_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing ADR-0029
- Missing substrate contracts or tools

#### Rollback / safe exit
Stop and restore missing files.

### Task: Phase 11 acceptance (design-only)

#### Intent
Run the Phase 11 acceptance suite (non-destructive).

#### Preconditions
- Phase 11 entry checklist passes

#### Command
```bash
make phase11.accept
```

#### Expected result
Acceptance marker written under `acceptance/PHASE11_ACCEPTED.md`.

#### Evidence outputs
`acceptance/PHASE11_ACCEPTED.md`

#### Failure modes
- Validation errors

#### Rollback / safe exit
Stop and remediate validation issues.

### Task: Phase 11 Part 1 entry checklist (plan-only)

#### Intent
Confirm Phase 11 Part 1 entry conditions for plan-only executors.

#### Preconditions
- Phase 11 design accepted
- Substrate executor scripts present

#### Command
```bash
make phase11.part1.entry.check
```

#### Expected result
Checklist written under `acceptance/PHASE11_PART1_ENTRY_CHECKLIST.md`.

#### Evidence outputs
`acceptance/PHASE11_PART1_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing executor scripts or Make targets

#### Rollback / safe exit
Stop and restore missing files.

### Task: Phase 11 Part 1 acceptance (plan-only)

#### Intent
Run the plan-only substrate acceptance suite (non-destructive).

#### Preconditions
- Phase 11 Part 1 entry checklist passes

#### Command
```bash
make phase11.part1.accept
```

#### Expected result
Acceptance marker written under `acceptance/PHASE11_PART1_ACCEPTED.md`.

#### Evidence outputs
`acceptance/PHASE11_PART1_ACCEPTED.md`

#### Failure modes
- Plan or DR dry-run validation errors

#### Rollback / safe exit
Stop and remediate validation issues.

### Task: Phase 11 Part 2 entry checklist (guarded execute)

#### Intent
Confirm Phase 11 Part 2 entry conditions for guarded execute mode.

#### Preconditions
- Phase 11 Part 1 accepted
- Execute policy present for substrate executors

#### Command
```bash
make phase11.part2.entry.check
```

#### Expected result
Checklist written under `acceptance/PHASE11_PART2_ENTRY_CHECKLIST.md`.

#### Evidence outputs
`acceptance/PHASE11_PART2_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing execute policy tooling
- Missing apply/verify/DR scripts

#### Rollback / safe exit
Stop and restore missing files.

### Task: Phase 11 Part 2 acceptance (guarded execute)

#### Intent
Run Phase 11 Part 2 acceptance suite (non-destructive; apply/DR execute are guarded).

#### Preconditions
- Phase 11 Part 2 entry checklist passes

#### Command
```bash
make phase11.part2.accept
```

#### Expected result
Acceptance marker written under `acceptance/PHASE11_PART2_ACCEPTED.md`.

#### Evidence outputs
`acceptance/PHASE11_PART2_ACCEPTED.md`

#### Failure modes
- Validation errors
- Missing execute policy

#### Rollback / safe exit
Stop and remediate validation issues.

### Task: Phase 11 Part 2 acceptance (guarded, read-only)

#### Intent
Run the Phase 11 Part 2 acceptance suite (non-destructive; verification is best-effort).

#### Preconditions
- Phase 11 Part 2 entry checklist passes

#### Command
```bash
make phase11.part2.accept
```

#### Expected result
Acceptance marker written under `acceptance/PHASE11_PART2_ACCEPTED.md`.

#### Evidence outputs
`acceptance/PHASE11_PART2_ACCEPTED.md`

#### Failure modes
- Validation errors

#### Rollback / safe exit
Stop and remediate validation issues.

### Task: Phase 11 Part 3 entry checklist (capacity guardrails)

#### Intent
Confirm Phase 11 Part 3 entry conditions for capacity/quota guardrails.

#### Preconditions
- Phase 11 Part 2 accepted
- Capacity schema + template present

#### Command
```bash
make phase11.part3.entry.check
```

#### Expected result
Checklist written under `acceptance/PHASE11_PART3_ENTRY_CHECKLIST.md`.

#### Evidence outputs
`acceptance/PHASE11_PART3_ENTRY_CHECKLIST.md`

#### Failure modes
- Missing capacity contracts or validators
- CI gate not wired

#### Rollback / safe exit
Stop and restore missing files.

### Task: Phase 11 Part 3 acceptance (capacity guardrails)

#### Intent
Run the Phase 11 Part 3 acceptance suite (non-destructive).

#### Preconditions
- Phase 11 Part 3 entry checklist passes

#### Command
```bash
make phase11.part3.accept
```

#### Expected result
Acceptance marker written under `acceptance/PHASE11_PART3_ACCEPTED.md`.

#### Evidence outputs
`acceptance/PHASE11_PART3_ACCEPTED.md`

#### Failure modes
- Capacity guard violations
- Missing capacity files

#### Rollback / safe exit
Stop and remediate capacity contracts or overrides.

### Task: Onboard a project to consume Fabric primitives (design-only)

#### Intent
Define intent-only bindings for a tenant; no provisioning or apply paths.

#### Preconditions
- Tenant contracts created from templates

#### Command
```bash
make tenants.validate
TENANT=all make tenants.evidence
```

#### Expected result
Tenant contracts validated; evidence packet available for review.

#### Evidence outputs
`evidence/tenants/<tenant-id>/<UTC>/...`

#### Failure modes
- Contract validation failures

#### Rollback / safe exit
Revise contract files and re-run.

---

## VM golden images

### Task: Validate VM image contracts

#### Intent
Validate VM image contracts against schema and semantics.

#### Preconditions
- Contracts present under `contracts/images/vm/`

#### Command
```bash
make images.vm.validate.contracts
```

#### Expected result
Contract validation PASS.

#### Evidence outputs
None by default.

#### Failure modes
- Schema validation failure

#### Rollback / safe exit
Fix contract files.

### Task: Local build/validate flow (guarded)

#### Intent
Build and validate VM qcow2 artifacts locally (opt-in).

#### Preconditions
- Local tooling installed
- Guards set for builds

#### Command
```bash
IMAGE_BUILD=1 I_UNDERSTAND_BUILDS_TAKE_TIME=1 \
make image.local.full IMAGE=ubuntu-24.04 VERSION=v1
```

#### Expected result
Local build + validation completes; evidence generated.

#### Evidence outputs
`evidence/images/vm/<image>/<version>/<UTC>/...`

#### Failure modes
- Missing tooling (qemu-img/guestfish)
- Validation failures

#### Rollback / safe exit
Stop and remediate local environment.

### Task: Proxmox template registration (guarded)

#### Intent
Register a qcow2 artifact as a Proxmox template (opt-in; token-only).

#### Preconditions
- Template registration allowlisted
- Guards set (execute mode)

#### Command
```bash
IMAGE_REGISTER=1 I_UNDERSTAND_TEMPLATE_MUTATION=1 \
REGISTER_REASON="initial register" \
ENV=samakia-dev TEMPLATE_NODE=proxmox1 TEMPLATE_STORAGE=pve-nfs TEMPLATE_VM_ID=9001 \
QCOW2=/path/to/image.qcow2 \
make image.template.register IMAGE=ubuntu-24.04 VERSION=v1
```

#### Expected result
Template registered and evidence packet written.

#### Evidence outputs
`evidence/images/vm/<image>/<version>/<UTC>/register/...`

#### Failure modes
- Policy allowlist violation
- SHA256 mismatch

#### Rollback / safe exit
Do not replace templates without explicit destructive guards.

---

## Phase entry and acceptance flows

### Task: Phase acceptance (read-only)

#### Intent
Run phase acceptance suites without mutation.

#### Preconditions
- Phase entry checklist passes

#### Command
```bash
make phase6.part2.accept
make phase7.accept
make phase8.part2.accept
```

#### Expected result
Acceptance PASS and markers created.

#### Evidence outputs
`acceptance/PHASE*_ACCEPTED.md`

#### Failure modes
- Missing prerequisites or policy failures

#### Rollback / safe exit
Stop; do not proceed to mutation.

---

## Operator command index

All operator-visible targets must be documented here or explicitly waived.

```
make consumers.bundle
make consumers.bundle.check
make consumers.disaster.check
make consumers.evidence
make consumers.gameday.dryrun
make consumers.gameday.execute.policy.check
make consumers.gameday.mapping.check
make consumers.ha.check
make consumers.validate
make dns.accept
make dns.ansible.apply
make dns.sdn.accept
make dns.tf.apply
make dns.tf.destroy
make dns.tf.plan
make dns.up
make ha.enforce.check
make ha.evidence.snapshot
make ha.placement.validate
make ha.proxmox.audit
make image.build
make image.build-next
make image.build-upload
make image.evidence.build
make image.evidence.validate
make image.list
make image.local.evidence
make image.local.full
make image.local.validate
make image.promote
make image.select
make image.template.register
make image.template.verify
make image.toolchain.build
make image.toolchain.full
make image.toolchain.validate
make image.tools.check
make image.upload
make image.validate
make image.version.test
make image.vm.build
make minio.accept
make minio.ansible.apply
make minio.backend.smoke
make minio.converged.accept
make minio.failure.sim
make minio.quorum.guard
make minio.sdn.accept
make minio.state.migrate
make minio.tf.apply
make minio.tf.destroy
make minio.tf.plan
make minio.up
make phase0.accept
make phase1.accept
make phase2.accept
make phase2.1.entry.check
make phase2.1.accept
make phase2.2.entry.check
make phase2.2.accept
make phase3.part1.accept
make phase3.part2.accept
make phase3.part3.accept
make phase4.entry.check
make phase4.accept
make phase5.entry.check
make phase5.accept
make phase6.entry.check
make phase6.part1.accept
make phase6.part2.accept
make phase6.part3.accept
make phase7.entry.check
make phase7.accept
make phase8.entry.check
make phase8.part1.accept
make phase8.part1.1.accept
make phase8.part1.2.accept
make phase8.part2.accept
make phase9.entry.check
make phase9.accept
make phase10.entry.check
make phase10.part1.entry.check
make phase10.part1.accept
make phase10.part2.entry.check
make phase10.part2.accept
make phase11.entry.check
make phase11.accept
make phase11.part1.entry.check
make phase11.part1.accept
make phase11.part2.entry.check
make phase11.part2.accept
make phase11.part3.entry.check
make phase11.part3.accept
make policy.check
make docs.operator.check
make docs.cookbook.lint
make substrate.contracts.validate
make substrate.capacity.guard
make substrate.capacity.evidence
make shared.ntp.accept
make shared.obs.accept
make shared.obs.ingest.accept
make shared.pki.accept
make shared.runtime.invariants.accept
make shared.sdn.accept
make shared.vault.accept
make tenants.schema.validate
make tenants.semantics.validate
make tenants.validate
make tenants.capacity.validate
make tenants.evidence
make tenants.doctor
make tenants.execute.policy.check
make tenants.dr.validate
make tenants.plan
make tenants.apply
make tf.apply
make tf.backend.init
make tf.init
make tf.plan
```
