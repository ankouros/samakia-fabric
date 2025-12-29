# Samakia Fabric – Operations Guide

This document describes **day-to-day operational procedures** for Samakia Fabric.

It is intended for:
- Operators
- SREs
- Platform engineers
- Automated agents performing operational tasks

This is a **runbook**, not a tutorial.

---

## Operational Scope

Samakia Fabric operations cover:
- Golden image lifecycle
- Terraform infrastructure lifecycle
- Ansible bootstrap and configuration
- Controlled recovery procedures

This document does NOT cover:
- Application operations
- Kubernetes workloads
- CI/CD pipelines
- Observability stacks

### TLS policy
- Default: strict verification
- Proxmox internal CA: install CA into the runner host trust store (no insecure flags)
- CI environments MUST use valid CA

## Runner Host Setup (Phase 1)

Samakia Fabric assumes Terraform and Ansible run from a trusted **runner host** with:
- Proxmox internal CA installed in the host trust store (strict TLS, no bypass flags)
- A canonical local environment file with API tokens and backend configuration

### Install Proxmox internal CA (runner host)

```bash
bash ops/scripts/install-proxmox-ca.sh
```

### Install runner env file (canonical)

Creates `~/.config/samakia-fabric/env.sh` with `chmod 600` (local-only; never committed):

```bash
bash ops/scripts/runner-env-install.sh
```

Validate (presence-only; secrets are never printed):

```bash
bash ops/scripts/runner-env-check.sh
```

### Install MinIO/S3 backend CA (only if required)

If your backend uses an internal CA not already trusted by the host:

```bash
bash ops/scripts/install-s3-backend-ca.sh
```

---

## Remote State Backend (MinIO HA)

Samakia Fabric uses a remote S3-compatible backend (MinIO) for Terraform state and locking (`use_lockfile = true`).

One-command deployment (non-interactive; requires runner env for Proxmox token + bootstrap SSH key):

```bash
make minio.up ENV=samakia-minio
```

### MinIO bootstrap lifecycle (canonical)

The MinIO environment is the Terraform backend provider, so it **must not depend on itself** at bootstrap time.

#### Terraform Backend Bootstrap Invariant

Invariant:
- `ENV=samakia-minio` must always start with **local state**:
  - `terraform init -backend=false`
- Only after MinIO is deployed and accepted may the state be migrated to remote S3.

Implementation detail (no manual steps):
- The Makefile bootstraps Terraform from a runner-local workspace that copies the env files **excluding** `backend.tf` (backend remains in Git), because Terraform cannot `plan/apply` against an uninitialized `backend "s3"` block.

Operational flow (non-interactive):
- `make backend.configure`
- `make minio.tf.apply ENV=samakia-minio` (local state; `-backend=false`)
- `make minio.ansible.apply ENV=samakia-minio`
- `make minio.accept`
- `make minio.state.migrate ENV=samakia-minio` (one-time migration to S3 backend)

Dry-run (no infra mutation):

```bash
DRY_RUN=1 make minio.up ENV=samakia-minio
```

This flow:
- Generates runner-local backend credentials and CA material under `~/.config/samakia-fabric/` (never committed).
- Installs the backend CA into the runner host trust store (strict TLS; requires non-interactive sudo).
- Applies Terraform (bootstrap-local state), bootstraps hosts, configures MinIO cluster + HAProxy VIP, and runs acceptance.
- Migrates the `samakia-minio` Terraform state into the remote backend.

After MinIO is up, initialize other env backends (per env):

```bash
ENV=samakia-prod make tf.backend.init
ENV=samakia-dns  make tf.backend.init
```

DNS becomes unblocked after the backend is available:

```bash
make dns.up ENV=samakia-dns
```


---

## Break-glass / Recovery

If you lose SSH access to a container, follow `OPERATIONS_BREAK_GLASS.md`.
This runbook is contract-safe: no root SSH re-enablement, no passwords, strict TLS, and no DNS dependency.

---

## Promotion Flow

Production upgrades are Git-driven and version-pinned:
- Image (`ubuntu-24.04-lxc-rootfs-vN.tar.gz`) → Proxmox template (`vztmpl/...-vN.tar.gz`) → Terraform env pin.

See `OPERATIONS_PROMOTION_FLOW.md`.

---

## DNS Infrastructure (infra.samakia.net)

Samakia Fabric DNS is a dedicated substrate:
- Single DNS endpoint for the entire estate: `192.168.11.100` (LAN VIP)
- Dual `dns-edge` nodes provide the VIP via VRRP and act as VLAN gateways (NAT egress)
- PowerDNS Authoritative runs on VLAN-only `dns-auth` nodes (master/slave)

One-command deployment (non-interactive):

```bash
make dns.up ENV=samakia-dns
```

Acceptance (non-interactive):

```bash
make dns.accept
```

Expected behavior:
- Exactly one edge holds `192.168.11.100` at any time.
- Exactly one edge holds VLAN gateway VIP `10.10.100.1` at any time.
- Queries for `infra.samakia.net` are answered authoritatively (dnsdist → PowerDNS).
- All other queries recurse via unbound (dnsdist → unbound).

Notes:
- Proxmox SDN objects for VLAN100 are created/validated during `terraform apply` (token-only via Proxmox API).
- `dns-auth-*` are VLAN-only; Ansible connects via `ProxyJump` through `dns-edge` (no DNS dependency).

---

## Golden Image Operations (Packer)

### When to Build a New Image

Build a new golden image only when:
- OS base updates are required
- SSH or OS hardening changes are required
- Image hygiene fixes are required (machine-id, host keys)
- Security advisories require it

Do NOT rebuild images for:
- User changes
- Application software
- Environment-specific configuration

### Image Build Procedure

```bash
	make image.build-next
```

Expected artifact:

```text
ubuntu-24.04-lxc-rootfs-v<N>.tar.gz
```

### Image Import to Proxmox

Upload the versioned rootfs artifact to Proxmox as an immutable LXC template (API token-based, no SSH).
Requires: `PM_API_URL`, `PM_API_TOKEN_ID`, `PM_API_TOKEN_SECRET`.

```bash
bash fabric-core/packer/lxc/scripts/upload-lxc-template-via-api.sh ./ubuntu-24.04-lxc-rootfs-v<N>.tar.gz
```

Validate:

```bash
pveam list <storage> | grep ubuntu-24.04
```

Rules:
- Never overwrite an existing template
- Always version images (`v1`, `v2`, `v3`, ...)

---

## Terraform Operations

### Where Terraform Is Run

Terraform MUST be executed only from:

```text
fabric-core/terraform/envs/<environment>
```

Never run Terraform inside `modules/`.

### Standard Terraform Workflow

Samakia Fabric uses a remote backend (MinIO/S3) with locking (`use_lockfile = true`).
Backend configuration is **not stored in Git**; it is initialized from runner env vars.

Initialize backend (per environment):

```bash
ENV=samakia-prod make tf.backend.init
```

Optional: migrate existing local state deliberately:

```bash
ENV=samakia-prod MIGRATE_STATE=1 make tf.backend.init
```

Plan/apply (non-interactive defaults, strict locking):

```bash
ENV=samakia-prod make tf.plan
ENV=samakia-prod make tf.apply
```

Destroy/recreate is acceptable and expected when:
- Template changes
- Storage changes
- Immutable attributes change

### Proxmox UI Tags (Terraform-managed metadata)

Terraform is the source of truth for Proxmox tags on LXCs. Tags are compact, deterministic, and semicolon-separated:

- `golden-vN;plane-<plane>;env-<env>;role-<role>`

Operational rules:
- Do not edit tags manually in Proxmox UI (treated as drift).
- `golden-vN` is derived from the pinned template artifact name (`*-vN.tar.gz`).
- Tags must not contain secrets, IPs, or spaces.

### Provider and Permissions

Terraform runs with a delegated Proxmox user.

Terraform MUST NOT:
- Require `root@pam`
- Modify LXC feature flags dynamically

If Terraform fails with permission errors:
- Verify whether the change violates delegated-user constraints
- Do NOT escalate privileges silently

---

## Drift Detection & Audit (read-only)

Run a non-destructive audit that detects:
- Terraform drift via `terraform plan` (no apply)
- Configuration drift via `ansible-playbook playbooks/harden.yml --check --diff` (no mutation)

This produces a timestamped local report under `audit/` (ignored by Git).

```bash
# Requires strict TLS trust (internal CA) and Proxmox API token env vars.
bash ops/scripts/drift-audit.sh samakia-prod
```

Interpretation:
- Any non-empty Terraform plan is “potential drift” and must be remediated via Git change + explicit apply/recreate.
- Any Ansible “would change” indicates policy drift and must be remediated via Ansible changes + deliberate re-run (non-check mode).

---

## Compliance & Signed Audit Exports

Generate immutable compliance snapshots (Terraform drift + Ansible check) and sign them for offline verification:

- `OPERATIONS_COMPLIANCE_AUDIT.md`
- `OPERATIONS_KEY_CUSTODY_DUAL_CONTROL.md` (dual-control / two-person signing)
- `OPERATIONS_EVIDENCE_NOTARIZATION.md` (optional TSA timestamp notarization)
- `OPERATIONS_APPLICATION_COMPLIANCE.md` (application-level compliance overlay)
- `OPERATIONS_POST_INCIDENT_FORENSICS.md` (post-incident forensics packets)
- `OPERATIONS_LEGAL_HOLD_RETENTION.md` (legal hold & retention governance for evidence)
- `OPERATIONS_CROSS_INCIDENT_CORRELATION.md` (cross-incident correlation: timelines + hypotheses, derived artifacts only)

---

## Incident Severity & Evidence Policy

Severity (S0–S4) determines evidence depth and signing requirements (not remediation actions):

- `INCIDENT_SEVERITY_TAXONOMY.md`

---

## Legal Hold & Retention

Legal hold is a **policy state** that overrides operational retention and prevents accidental evidence expiry/deletion (no deletion automation is implemented here).

- `LEGAL_HOLD_RETENTION_POLICY.md`
- `OPERATIONS_LEGAL_HOLD_RETENTION.md`

---

## Security Threat Modeling

Threat modeling is analysis-only and informs prioritization (it does not enforce controls or mutate systems):
- `SECURITY_THREAT_MODELING.md`

Related inputs:
- `INCIDENT_SEVERITY_TAXONOMY.md`
- `COMPLIANCE_CONTROLS.md`
- `OPERATIONS_POST_INCIDENT_FORENSICS.md`
- `OPERATIONS_CROSS_INCIDENT_CORRELATION.md`

---

## HA / Failure Domains

Proxmox HA is enabled deliberately per workload, with explicit placement/failure-domain thinking and operator-run recovery steps.

- `OPERATIONS_HA_FAILURE_DOMAINS.md`
- `OPERATIONS_HA_FAILURE_SIMULATION.md` (GameDays / failure simulation runbook)

---

## Pre-Release Readiness Audit

Formal Go/No-Go gate that aggregates platform, drift, compliance, incident posture, and risk signals into a signable readiness packet (analysis-only).

- `OPERATIONS_PRE_RELEASE_READINESS.md`

---

## Ansible Operations

### Bootstrap Procedure (New LXC)

1. Terraform creates the container
2. Temporary root SSH access (key-only)
3. Run bootstrap playbook

```bash
ansible-playbook playbooks/bootstrap.yml -u root -e @secrets/authorized_keys.yml
```

`secrets/authorized_keys.yml` must define `bootstrap_authorized_keys` and is not committed.
Bootstrap will fail if keys are missing to avoid lockout.

Verify:
- Non-root user exists
- SSH keys installed
- Passwordless sudo
- Root SSH access disabled

### Normal Configuration Runs

```bash
ansible-playbook playbooks/site.yml
```

Rules:
- Must be idempotent
- Must not assume fresh hosts
- Must not rely on interactive input

---

## SSH Access Model

Rules:
- SSH is key-only
- Password authentication is forbidden
- Root SSH access is temporary
- Long-term access uses a non-root operator user

Validation:

```bash
ssh <user>@<host>
sudo -i
```

Failure to enforce this model is considered a security incident.

---

## LXC Lifecycle (Replace / Blue-Green)

Preferred operational patterns (deterministic, GitOps-driven):
- Replace in-place (same VMID) for immutable upgrades
- Blue/green (new VMID) for cutovers

Runbook:
- `OPERATIONS_LXC_LIFECYCLE.md`

Make targets (guidance; never auto-apply):

```bash
ENV=samakia-prod make ops.replace.inplace
ENV=samakia-prod make ops.bluegreen.plan
```

SSH trust rotation after replace/recreate (never disable StrictHostKeyChecking):

```bash
make ssh.trust.rotate HOST=<ip>
make ssh.trust.verify HOST=<ip>
```

---

## Failure and Recovery Scenarios

### Terraform Apply Failure

Steps:
1. Do NOT re-run blindly
2. Read the error
3. Determine the cause:
   - Permission issue
   - API normalization issue
   - Immutable attribute change
4. Fix configuration
5. Re-run `terraform plan`

### Broken Container

Preferred recovery:
1. Destroy container via Terraform
2. Recreate from golden image
3. Re-run Ansible

Manual repair inside containers is discouraged.

### SSH Lockout

If locked out:
1. Access via Proxmox console
2. Fix SSH configuration
3. Re-apply Ansible bootstrap

Never re-enable password authentication as a workaround.

---

## State Management

Terraform state:
- Must be treated as critical data
- Must not be edited manually
- Remote state (S3/MinIO) is the canonical model (Phase 1)

State loss recovery:
- Re-import resources where possible
- Reconcile state carefully
- Avoid force-destroy without understanding impact

---

## Logging and Auditing

Operational logs include:
- Terraform plan/apply output
- Ansible playbook output
- Proxmox task logs

All destructive actions should be traceable via:
- Git history
- Terraform state history
- Proxmox task logs

---

## Change Management

All changes must be:
- Code-driven
- Version-controlled
- Reviewed

Emergency changes:
- Must be documented after the fact
- Must be reconciled back into code

“No manual-only fixes” is a hard rule.

---

## Operational Anti-Patterns (Do Not Do)

- Editing containers manually
- Running Terraform as `root@pam`
- Baking users into images
- Hot-patching Proxmox outside code
- Using passwords for SSH
- Treating containers as pets

---

## Acceptance & Verification (Phase 1)

Run the Phase 1 acceptance suite from repo root (safe output; no secrets printed):

```bash
ENV=samakia-prod make phase1.accept
```

This runs:
- `bash fabric-ci/scripts/lint.sh`
- `bash fabric-ci/scripts/validate.sh`
- env parity checks (dev/staging/prod shape)
- runner env checks (strict TLS + token-only)
- inventory parse + DHCP/IP sanity
- Terraform validate + plan (`-input=false`)

---

## Operational Philosophy

Samakia Fabric follows a rebuild-over-repair philosophy.

If a system breaks:
- Replace it
- Rebuild it
- Reapply configuration

This reduces entropy and operational risk.

---

## Final Notes

Samakia Fabric is designed for calm operations.

If an operational action feels rushed or unclear:
- Stop
- Read the documentation
- Fix the process, not the symptom
