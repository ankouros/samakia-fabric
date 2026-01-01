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
