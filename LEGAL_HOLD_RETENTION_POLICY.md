# Legal Hold & Evidence Retention Policy (Governance)

This policy defines **evidence retention** and **legal hold** governance for Samakia Fabric evidence artifacts:
- compliance snapshots
- application evidence bundles
- forensics packets

This is governance-first:
- Legal hold is a **policy state**, not a technical lock on running systems.
- Automation may **label, track, and report** hold status, but must not mutate runtime.

Hard constraints (platform contracts):
- Evidence is read-only; no remediation, no deletion by default
- No secrets in Git or evidence artifacts
- Evidence may be signed (single/dual-control) and optionally TSA-notarized
- Offline verification must remain possible

This document is not legal advice.

---

## A) Legal hold concepts

### What a legal hold is
A legal hold is a formal instruction to **preserve relevant evidence** beyond normal operational retention, due to:
- legal request
- regulator notice
- internal investigation
- high-severity incident with potential legal impact

Legal hold applies to evidence artifacts (directories/files), not to live systems.

### What triggers a legal hold (examples)
- Incident severity S3/S4 (confirmed compromise or systemic/legal impact)
- written request from legal authority (per organization policy)
- regulator inquiry requiring preservation of audit evidence
- security incident involving potential data exposure (policy-approved)

### Operational retention vs legal hold
- **Operational retention**: routine retention windows for troubleshooting and audits.
- **Legal hold**: overrides retention, prevents deletion/expiry of scoped evidence until formally released.

Legal hold always wins over operational retention.

---

## B) Evidence types & default retention guidance

Retention is policy-driven; use these as defensible defaults and adjust per organization requirements.

### Evidence types
- **Compliance snapshots**: substrate drift/audit snapshots (`compliance/<env>/snapshot-*`)
- **Application evidence**: per-service evidence bundles (`compliance/<env>/app-evidence-*/snapshot-*`)
- **Forensics packets**: incident evidence bundles (`forensics/<incident-id>/snapshot-*`)
- **Audit reports**: signed reports generated from evidence (if any)
- **Supporting artifacts**: manifests, signatures, TSA tokens, metadata, references

### Default retention table (minimum vs recommended)

| Evidence type | Default minimum | Default recommended | Notes |
|---|---:|---:|---|
| Compliance snapshots (prod) | 90 days | 12 months | supports audits + change traceability |
| Compliance snapshots (dev) | 30 days | 90 days | lower governance; avoid over-collection |
| Application evidence (tier-critical) | 180 days | 24 months | aligns to release/audit cycles |
| Application evidence (tier-noncritical) | 90 days | 12 months | |
| Forensics packets (S2) | 12 months | 24 months | may become legal hold if escalated |
| Forensics packets (S3) | 24 months | 36+ months | often legal review required |
| Forensics packets (S4) | 36+ months | per legal directive | expect legal hold |
| TSA tokens / signatures / manifests | same as parent | same as parent | never separate from parent packet |

Jurisdictional notes (non-advice):
- Retention may be constrained by privacy policies and regulations.
- Do not retain sensitive logs/PII unless authorized and policy-approved.

---

## C) Hold lifecycle (declare → maintain → release)

### Declaration
Legal hold declaration requires:
- `hold_id` (unique, non-sensitive identifier)
- scope definition (what is held)
- authorized declarer identity and timestamp (UTC)
- reason (non-sensitive summary)
- review date (when to re-evaluate)

Hold declaration is recorded as **labels** added alongside evidence (see labeling model).

### Scope definition (examples)
Scope can be any combination of:
- environment (`samakia-prod`, `samakia-dev`)
- incident ID (`INC-2025-0012`)
- evidence path(s) (specific snapshot directories)
- service group(s) (application evidence directories)

Prefer narrow scope. Expand only when justified and approved.

### Maintenance
During hold:
- evidence must not be deleted or pruned
- transfers (where stored) must be recorded externally (ticket/tracking system)
- any exceptions must be recorded (see Exceptions)

### Release
Release must be explicit:
- approved by legal authority (or delegated authority per org policy)
- recorded with timestamp, approver identity, and reason
- evidence retention reverts to operational policy after release

Release is recorded as a label event (no deletion is performed automatically).

### Exceptions
Exceptions (e.g., missing evidence, partial evidence, urgent storage constraints) must be:
- explicitly approved
- documented with a reference ID
- captured as an add-on record in the label pack

---

## D) Roles & approvals (separation of duties)

Roles:
- **Legal authority**: authorizes holds and releases (or delegates authority)
- **Security lead**: recommends holds for S3/S4; approves sensitive evidence scope
- **Platform operator**: executes labeling, ensures evidence is preserved, reports status
- **Auditor**: verifies integrity/signatures/TSA and reviews hold records

Approval matrix (default):
- Declare hold:
  - S2: incident commander + security lead (optional legal)
  - S3/S4: security lead + legal authority
- Release hold:
  - legal authority (mandatory)
- Exceptions:
  - legal + security lead (mandatory for S3/S4)

Dual-control expectations:
- For holds that apply to S3/S4 evidence, signing the hold record should use dual-control (two-person rule) where required by policy.
