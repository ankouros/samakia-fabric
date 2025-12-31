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

### Task: Validate tenant contracts

#### Intent
Validate tenant (project) bindings against schema and semantics.

#### Preconditions
- Tenant contracts present under `contracts/tenants/`

#### Command
```bash
make tenants.validate
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
make policy.check
make docs.operator.check
make docs.cookbook.lint
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
make tf.apply
make tf.backend.init
make tf.init
make tf.plan
```
