# Legal Hold & Retention — Operations Runbook (03:00-safe)

This runbook operationalizes:
- `LEGAL_HOLD_RETENTION_POLICY.md` (governance)
- evidence labeling (non-destructive)
- verification workflows (offline-capable)

Hard rules:
- No evidence deletion is implemented here.
- No modification of evidence contents; only add-on labels are created.
- No network calls required for labeling and verification.

---

## 1) What is under scope

Evidence locations (default, local artifacts; not committed to Git):
- Compliance snapshots: `compliance/<env>/snapshot-<UTC>/`
- Application evidence: `compliance/<env>/app-evidence-<service>/snapshot-<UTC>/`
- Forensics packets: `forensics/<incident-id>/snapshot-<UTC>/`

Legal hold labels are stored under:
- `<evidence_dir>/legal-hold/`

These labels are excluded from the evidence `manifest.sha256` by design and can be signed/notarized separately.

---

## 2) Declare a legal hold (non-destructive)

Inputs you must have:
- `hold_id` (unique identifier, non-sensitive)
- `declared_by` (human identity)
- `reason` (non-sensitive summary)
- `review_date` (UTC date; policy-driven)
- evidence path(s) to hold

Command (per evidence directory):
```bash
bash ops/scripts/legal-hold-manage.sh declare \
  --path <evidence_dir> \
  --hold-id <HOLD-ID> \
  --declared-by "<name>" \
  --reason "<non-sensitive summary>" \
  --review-date 2026-01-31
```

What it does:
- creates `legal-hold/LEGAL_HOLD`
- creates `legal-hold/hold.json`
- creates `legal-hold/manifest.sha256` (for the label pack, not the evidence pack)

It does not:
- delete anything
- alter the evidence `manifest.sha256`
- sign anything

---

## 3) Sign / dual-sign / notarize the legal hold record (add-on evidence)

Signing target is:
- `<evidence_dir>/legal-hold/manifest.sha256`

### Single signature
```bash
export COMPLIANCE_SNAPSHOT_DIR="<evidence_dir>/legal-hold"
export COMPLIANCE_GPG_KEY="<FPR>"

bash ops/scripts/compliance-snapshot.sh samakia-prod
```

### Dual-control (two-person)
Create dual-control markers in the label pack if policy requires it:
```bash
bash ops/scripts/legal-hold-manage.sh require-dual-control --path <evidence_dir>
```

Then have both custodians sign:
```bash
export COMPLIANCE_SNAPSHOT_DIR="<evidence_dir>/legal-hold"
export COMPLIANCE_GPG_KEYS="<FPR_A>,<FPR_B>"
export ALLOW_PARTIAL_SIGNATURE=1

bash ops/scripts/compliance-snapshot.sh samakia-prod
```

### Optional TSA notarization (RFC 3161)
```bash
export COMPLIANCE_SNAPSHOT_DIR="<evidence_dir>/legal-hold"
export COMPLIANCE_TSA_URL="https://tsa.example.org/tsa"
export COMPLIANCE_TSA_CA="/path/to/tsa-ca-bundle.pem"

bash ops/scripts/compliance-snapshot.sh samakia-prod
```

Verification (offline):
```bash
bash ops/scripts/verify-compliance-snapshot.sh <evidence_dir>/legal-hold
```

---

## 4) List active holds and validate completeness

List holds (scans `compliance/` and `forensics/`):
```bash
bash ops/scripts/legal-hold-manage.sh list
```

Validate a specific hold pack:
```bash
bash ops/scripts/legal-hold-manage.sh validate --path <evidence_dir>
```

---

## 5) Release a hold (record only; no deletion)

Release requires explicit approval per policy.

Command:
```bash
bash ops/scripts/legal-hold-manage.sh release \
  --path <evidence_dir> \
  --released-by "<name>" \
  --reason "<non-sensitive summary>"
```

Then sign/notarize the updated label pack:
```bash
export COMPLIANCE_SNAPSHOT_DIR="<evidence_dir>/legal-hold"
bash ops/scripts/compliance-snapshot.sh samakia-prod
```

No deletion occurs. Retention review is a separate, explicitly authorized process.

---

## 6) Retention review & purge workflow (docs-only; no tooling)

Retention review procedure (manual):
1. Identify evidence older than its operational retention window.
2. Check for `legal-hold/LEGAL_HOLD` marker:
   - if present: do not delete; hold overrides retention
3. Require explicit approval for any deletion:
   - incident commander + security lead (minimum)
   - legal authority if held or S3/S4 related
4. Record deletion approvals and outcomes externally (ticketing system).
5. Verify that remaining evidence packets still verify offline.

This repository intentionally does not implement deletion scripts.
