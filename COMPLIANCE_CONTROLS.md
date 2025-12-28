# Application Compliance Controls (Overlay)

This catalog defines **application-level controls** that sit above the Samakia Fabric substrate.

Scope notes:
- These controls do not change the substrate contracts (images/Terraform/Ansible/GitOps).
- Evidence is **read-only** and must not contain secrets.
- Evidence bundles are designed to be **signed** (single/dual-control) and optionally **TSA-notarized** using the existing evidence workflow.

---

## Control format

Each control is specified with:
- **Control ID**
- **Objective**
- **Scope** (app types / services)
- **Required evidence**
- **Collection method** (commands / artifacts)
- **Frequency**
- **Pass/Fail criteria**
- **Owner**

---

## Identity & Access (IAM)

### APP-IAM-001 — Service identity and ownership declared
- Objective: Every service has an owner and a declared purpose.
- Scope: all services
- Required evidence: service compliance profile file (metadata)
- Collection method: include the profile file path in the app evidence bundle metadata
- Frequency: on change / release
- Pass/Fail: fail if owner/criticality/data classification are missing
- Owner: service owner

### APP-IAM-002 — Least privilege for service-to-service access
- Objective: Service credentials grant only required permissions.
- Scope: APIs, workers, databases clients
- Required evidence: redacted access policy summary + principals list + scope list
- Collection method: attach a **redacted** policy export or a pointer to the policy source (ticket ID / repo path)
- Frequency: quarterly + on policy change
- Pass/Fail: fail if broad wildcard privileges are present without exception record
- Owner: service owner + platform security

### APP-IAM-003 — Admin access paths are explicit
- Objective: Human/admin operations are documented and audited.
- Scope: all services
- Required evidence: runbook link + audit log location(s)
- Collection method: include runbook reference and log sink configuration evidence (redacted)
- Frequency: on change
- Pass/Fail: fail if no admin/runbook path is documented
- Owner: service owner

---

## Secrets Management

### APP-SEC-001 — Secrets are never committed
- Objective: No secrets in Git and no secrets in evidence bundles.
- Scope: all services
- Required evidence: secret scanning result reference (tool output pointer) + config fingerprint excluding secrets
- Collection method: evidence bundle includes allowlisted config fingerprints; denylisted files are refused
- Frequency: per release
- Pass/Fail: fail if secrets appear in tracked config or evidence
- Owner: service owner + reviewers

### APP-SEC-002 — Secret rotation plan exists
- Objective: Keys/tokens can be rotated without downtime or lockout where applicable.
- Scope: services with credentials
- Required evidence: rotation procedure + last rotation record (ticket/reference)
- Collection method: include runbook section + ticket IDs (no secrets)
- Frequency: per policy (e.g. 90/180 days)
- Pass/Fail: fail if no rotation procedure exists for long-lived secrets
- Owner: service owner

---

## Encryption In Transit

### APP-TLS-001 — External interfaces use TLS
- Objective: User-facing endpoints and admin APIs use TLS.
- Scope: APIs, frontends
- Required evidence: endpoint list + TLS termination location + certificate chain evidence (public)
- Collection method: include endpoint inventory and TLS config fingerprints (no private keys)
- Frequency: per release / cert rotation
- Pass/Fail: fail if plaintext endpoints exist without exception and compensating controls
- Owner: platform + service owner

### APP-TLS-002 — Internal service traffic policy
- Objective: Internal traffic is protected per classification (TLS or mTLS where required).
- Scope: services with sensitive data
- Required evidence: policy statement + config evidence (redacted)
- Collection method: include declared policy + config fingerprint of relevant proxy/app settings
- Frequency: quarterly
- Pass/Fail: fail if policy is missing for sensitive services
- Owner: platform security

---

## Encryption At Rest (where applicable)

### APP-DATA-001 — Data storage locations and encryption expectations documented
- Objective: Know where data lives and what encryption applies.
- Scope: stateful services (Postgres, Redis/Dragonfly, MQ, file storage)
- Required evidence: data stores list + encryption status statement + backup location statement
- Collection method: include profile fields + pointers to storage configuration (no credentials)
- Frequency: on change
- Pass/Fail: fail if storage locations are unknown/undocumented
- Owner: service owner

---

## Logging & Audit Trails

### APP-LOG-001 — Structured logging enabled and documented
- Objective: Services emit logs that can be correlated and retained.
- Scope: all services
- Required evidence: log format statement + log sink location + example schema (no secrets)
- Collection method: include logging config fingerprints and log location references
- Frequency: per release
- Pass/Fail: fail if logs are disabled or cannot be located
- Owner: service owner

### APP-LOG-002 — Audit logging for security-relevant actions
- Objective: Security-relevant actions are auditable.
- Scope: APIs with authz decisions, admin actions
- Required evidence: audit event definitions + sink/retention
- Collection method: include event list and config fingerprints
- Frequency: quarterly
- Pass/Fail: fail if no audit events exist for sensitive services
- Owner: service owner + security

---

## Vulnerability Management & Patching

### APP-VULN-001 — Dependency update cadence defined
- Objective: Dependency drift is controlled.
- Scope: services with dependencies (Node, Python, etc.)
- Required evidence: dependency lockfile fingerprint + update policy
- Collection method: include lockfile hash + policy statement
- Frequency: per release + monthly review
- Pass/Fail: fail if no cadence exists or lockfiles are missing for applicable stacks
- Owner: service owner

### APP-VULN-002 — Vulnerability scan evidence (integration)
- Objective: Vulnerabilities are detected and tracked.
- Scope: all services
- Required evidence: scan results reference (SBOM/scanner outputs) or documented gap with plan
- Collection method: include artifact pointer(s) and ticket IDs; do not implement scanners here
- Frequency: per release
- Pass/Fail: fail if no evidence/pointer exists for critical services
- Owner: service owner + security

---

## Backup & Restore

### APP-BACKUP-001 — RPO/RTO declared and tested
- Objective: Recovery objectives exist and are validated.
- Scope: stateful services
- Required evidence: RPO/RTO values + last restore test record
- Collection method: include profile fields + ticket/runbook references
- Frequency: quarterly + after major changes
- Pass/Fail: fail if no restore test record exists for critical stateful services
- Owner: service owner + ops

### APP-BACKUP-002 — Backup scope and exclusion rules documented
- Objective: Backups capture required state and exclude secrets appropriately.
- Scope: stateful services
- Required evidence: backup inclusion list + exclusion list + storage target statement
- Collection method: include configuration fingerprint (redacted) + runbook references
- Frequency: on change
- Pass/Fail: fail if scope is undefined
- Owner: service owner

---

## Change Management (Promotion/Rollback)

### APP-CHANGE-001 — Release identity ties to Git commit
- Objective: Releases are traceable to Git (GitOps alignment).
- Scope: all services
- Required evidence: service version + Git commit in evidence metadata
- Collection method: include `git rev-parse` output and build version if available
- Frequency: per release
- Pass/Fail: fail if release cannot be tied to a commit
- Owner: service owner

### APP-CHANGE-002 — Rollback procedure exists and is boring
- Objective: Operators can revert safely.
- Scope: all services
- Required evidence: rollback runbook + last drill reference (if applicable)
- Collection method: include runbook link + ticket IDs
- Frequency: quarterly for critical services
- Pass/Fail: fail if no rollback path exists
- Owner: service owner + ops

---

## Incident Response (break-glass linkage)

### APP-IR-001 — Service-specific break-glass steps documented
- Objective: When the service is down, operators have a safe procedure.
- Scope: all services
- Required evidence: service runbook that references platform break-glass rules
- Collection method: include runbook path + confirmation that it does not violate substrate constraints
- Frequency: on change
- Pass/Fail: fail if no incident runbook exists for tier-critical services
- Owner: service owner + ops

---

## Data Retention & Minimization

### APP-DATA-RET-001 — Retention policy declared
- Objective: Data lifecycle is intentional.
- Scope: services storing data
- Required evidence: retention statement + deletion/archival procedure
- Collection method: include policy statement and runbook references
- Frequency: yearly + on change
- Pass/Fail: fail if retention is unknown for sensitive data
- Owner: service owner + compliance

---

## Supply Chain Integrity

### APP-SC-001 — Build inputs are pinned
- Objective: Builds are deterministic enough to audit.
- Scope: all services
- Required evidence: lockfile fingerprints and/or version pinning evidence
- Collection method: include hashes of lockfiles and build config (no secrets)
- Frequency: per release
- Pass/Fail: fail if build inputs float without policy exception
- Owner: service owner

---

## Environment Separation

### APP-ENV-001 — Dev/prod separation declared and enforced by process
- Objective: Production data and changes are controlled.
- Scope: all services
- Required evidence: environment mapping + access boundary statement
- Collection method: include service profile fields and access policy references (no secrets)
- Frequency: on change
- Pass/Fail: fail if production access boundary is undefined
- Owner: platform + service owner
