# Application-Level Compliance (Overlay) — Operations Runbook

This runbook describes how to apply an application-level compliance overlay on top of Samakia Fabric’s substrate.

This is intentionally **policy + evidence patterns**, not enforcement:
- No configuration mutation during evidence collection
- No auto-remediation
- No background daemons/cron jobs (documented only)
- No Kubernetes assumptions (LXC-first)

---

## A) Declare a service compliance profile

Each service should have a small metadata file (docs-only) that becomes part of the evidence trail.

Recommended location:
- `services/<service_name>/compliance.yml` (or equivalent in your repo layout)

Required fields (minimum):
- `name`
- `owner`
- `criticality` (e.g. `tier-critical` / `tier-noncritical`)
- `data_classification` (e.g. `public` / `internal` / `confidential`)
- `dependencies` (e.g. Postgres, RabbitMQ, Redis)
- `rpo` / `rto` (targets)
- `log_locations` (where logs/audit logs are expected to be found)
- `backup_scope` (what must be backed up)
- `change_model` (promotion/rollback expectations)

Hard rule:
- Never put secrets in the profile file.

---

## B) Collect evidence (manual, repeatable)

Evidence collection should be environment-scoped and service-scoped.

### 1) Create an evidence snapshot directory

Use the helper script (read-only) if appropriate:
```bash
bash ops/scripts/app-compliance-evidence.sh <env> <service_name> <service_root_dir> --config paths.txt
```

Or follow the model in `COMPLIANCE_EVIDENCE_MODEL.md` and assemble files manually.

### 2) Collect “config fingerprints” (redacted)

Collect hashes (not contents) of allowlisted config files, for example:
- application config templates
- deployment descriptors
- lockfiles (`package-lock.json`, `pnpm-lock.yaml`, etc.)
- public TLS certificate chains (not private keys)

If a config file contains secrets:
- generate a redacted copy for evidence, and fingerprint the redacted copy instead.

### 3) Collect runtime version info (read-only)

Provide evidence of what is running:
- service version / build ID
- Git commit (or container image digest if used)
- runtime environment (OS version inside CT, language runtime versions)

How to collect depends on workload.
Typical examples (run as `samakia`, read-only):
- `cat /etc/os-release`
- `systemctl status <service>` (if applicable)
- `ss -lntp` (port-level evidence; do not include tokens)
- application `/health` endpoint output (sanitized)

### 4) Logging and audit settings verification

Evidence should prove:
- where logs go
- audit events exist for sensitive actions

Collect:
- config fingerprints for logging settings
- references to log sinks (paths/URLs without credentials)

### 5) Backup status evidence

Evidence should prove:
- backup scope and schedule (policy)
- most recent backup existence (pointer) and last restore test record (ticket)

Do not implement backup tooling here; attach pointers and runbook references.

### 6) Vulnerability evidence pointers (integration only)

This overlay does not introduce scanners.

Attach:
- SBOM identifiers or scan report IDs/URLs (no credentials)
- ticket IDs for remediation work

---

## C) Sign and (optionally) notarize app evidence

App evidence is signed exactly like substrate evidence:
- The integrity target is the evidence bundle’s `manifest.sha256`.

### Single-signature signing
```bash
export COMPLIANCE_SNAPSHOT_DIR="compliance/<env>/app-evidence-<service>/snapshot-<UTC>"
export COMPLIANCE_GPG_KEY="<FPR>"

bash ops/scripts/compliance-snapshot.sh <env>
```

### Dual-control (two-person) signing
Create `DUAL_CONTROL_REQUIRED` and `approvals.json` per `COMPLIANCE_EVIDENCE_MODEL.md`, then have both custodians sign:
```bash
export COMPLIANCE_SNAPSHOT_DIR="compliance/<env>/app-evidence-<service>/snapshot-<UTC>"
export COMPLIANCE_GPG_KEYS="<FPR_A>,<FPR_B>"
export ALLOW_PARTIAL_SIGNATURE=1

bash ops/scripts/compliance-snapshot.sh <env>
```

Custody/governance:
- `OPERATIONS_KEY_CUSTODY_DUAL_CONTROL.md`

### Optional TSA notarization (RFC 3161)
```bash
export COMPLIANCE_TSA_URL="https://tsa.example.org/tsa"
export COMPLIANCE_TSA_CA="/path/to/tsa-ca-bundle.pem"

bash ops/scripts/compliance-snapshot.sh <env>
```

Runbook:
- `OPERATIONS_EVIDENCE_NOTARIZATION.md`

---

## D) Present to auditors

Recommended “audit packet” contents:
- `COMPLIANCE_CONTROLS.md` (control catalog)
- service compliance profile (`compliance.yml`)
- signed evidence bundle directory:
  - `metadata.json`
  - `manifest.sha256` + signature(s)
  - optional TSA token
  - supporting evidence files

Mapping pattern:
- For each control ID (e.g. `APP-LOG-002`), include:
  - where evidence lives (path)
  - what “pass” means (criteria)
  - date/time (UTC) and signer fingerprints

Hard rule:
- Unsigned evidence is not compliance evidence. It is only raw data.
