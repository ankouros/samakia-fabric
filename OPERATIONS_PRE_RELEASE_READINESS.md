# Pre-Release Readiness Audit (Go / No-Go Gate) — Evidence-referenced, Human-approved

This runbook defines a **formal, repeatable** pre-release readiness audit for Samakia Fabric.

Hard rules:
- This is decision support, not approval automation.
- No infrastructure mutation, no remediation, no enforcement.
- Evidence is referenced (path + hash), not copied or modified.
- Signing / dual-control / TSA notarization remain authoritative when required by policy.

Guiding principle:
A release should only ship when the risk is known, documented, and accepted — not when checks merely pass.

---

## A) Purpose & Authority

### What this audit is
- A structured consolidation of signals (platform health, drift, evidence completeness, incident posture, risk).
- A defensible Go/No-Go recommendation with explicit risk acceptance when needed.
- An auditable “readiness packet” that can be signed/dual-signed/TSA-notarized.

### What this audit is not
- Automatic approval.
- An enforcement gate in CI.
- A replacement for change reviews or operational ownership.

### Who can initiate
- Platform operator / SRE on duty
- Release engineer

### Who must sign off (roles)
- **Platform/SRE**: platform health, HA readiness, operational risk
- **Security**: incident posture, threat/risk review, evidence integrity requirements
- **Service owner(s)**: application readiness, backup/restore evidence, known issues
- **Legal** (when applicable): legal holds, regulator-driven requirements

---

## B) Readiness Checklist (Mandatory, Evidence-referenced)

All items must be explicitly marked:
- `PASS`
- `FAIL`
- `ACCEPTED RISK` (with written acceptance + approver)
- `N/A` (with justification)

Evidence rule:
- Reference evidence by `path:sha256=<hash>` (hash should come from the evidence `manifest.sha256` when available).
- Do not paste large evidence content into the readiness packet.

### B1) Platform health (Proxmox / HA)
- Quorum healthy (`pvecm status`)
- HA manager healthy (`pve-ha-manager status`, `pve-ha-crm/lrm` active)
- No unresolved HA alerts/flapping
- Recent HA GameDay exists (dev required; prod recommended) OR justified exception
  - Runbook: `OPERATIONS_HA_FAILURE_SIMULATION.md`

### B2) Configuration integrity (Terraform / Ansible)
- Latest Terraform plan is clean (or changes are understood and intentional)
- Drift audit reviewed (Terraform + Ansible check-only)
  - Script: `ops/scripts/drift-audit.sh`
- No unmanaged critical resources (explicitly documented if any exist)

### B3) Compliance & evidence integrity
- Latest compliance snapshot exists for the target env (prod at minimum)
- Snapshot is signed (single or dual-control per policy)
- TSA notarized if policy requires
- Verification performed offline-capable:
  - `ops/scripts/verify-compliance-snapshot.sh`
- No open legal holds blocking release OR release explicitly approved under hold constraints
  - Policy: `LEGAL_HOLD_RETENTION_POLICY.md`
  - Runbook: `OPERATIONS_LEGAL_HOLD_RETENTION.md`

### B4) Application readiness (overlay)
- App-level compliance evidence collected for in-scope services (or justified exception)
  - Controls: `COMPLIANCE_CONTROLS.md`
  - Runbook: `OPERATIONS_APPLICATION_COMPLIANCE.md`
- Known vulnerabilities assessed and documented (no scanning performed here)
- Backup & restore evidence exists (RPO/RTO + last restore test reference)

### B5) Incident posture
- No unresolved S3/S4 incidents
- Cross-incident correlation reviewed if patterns exist (repeated S2, any S3/S4)
  - Runbook: `OPERATIONS_CROSS_INCIDENT_CORRELATION.md`
- Forensics packets closed or explicitly accepted (facts preserved, scope recorded)
  - Runbook: `OPERATIONS_POST_INCIDENT_FORENSICS.md`

### B6) Threat & risk review
- Threat model reviewed for this release scope:
  - `SECURITY_THREAT_MODELING.md`
- No unaccepted high-risk residuals (or explicit acceptance recorded)
- Any new risks introduced by the release are explicitly acknowledged

---

## C) Go / No-Go Decision Model (Explicit)

### Mandatory No-Go conditions
No-Go if any of these are true:
- Cluster not quorate or HA manager unhealthy.
- Drift audit indicates unexpected/unknown changes in prod.
- Compliance snapshot missing or fails verification.
- Any unresolved S4 incident or active suspected compromise.
- Release would violate a legal hold requirement or regulator instruction.
- Operator cannot articulate rollback/recreate path.

### Go with accepted risk (requires explicit acceptance)
Go is allowed only if:
- All `FAIL` items are resolved OR downgraded to `ACCEPTED RISK` with approver and rationale.
- Accepted risks are time-bounded where possible (review date).
- High-risk accepted items have Security sign-off (and Legal if relevant).

### Escalation rules
Escalate before proceeding if:
- Any S3/S4 incident relevance is uncertain.
- Evidence integrity is uncertain (missing signatures, unverifiable artifacts).
- Risk acceptance would materially increase blast radius (cluster-wide exposure).

---

## D) Readiness Audit Packet (Signable Output)

Create a new local packet (ignored by Git) per release:
```text
release-readiness/<release-id>/
  metadata.json
  checklist.md
  evidence-refs.txt
  risk-acceptance.md        # only if needed
  manifest.sha256
  # optional signatures / TSA (produced after manifest exists)
  manifest.sha256.asc
  manifest.sha256.asc.a
  manifest.sha256.asc.b
  manifest.sha256.tsr
  tsa-metadata.json
```

Rules:
- This packet is **derived** and must not modify the underlying evidence packs.
- Evidence is referenced by path/hash.
- No secrets.
- Packet can be signed/dual-signed/TSA-notarized using existing tooling (sign-only mode):
  - `COMPLIANCE_SNAPSHOT_DIR="release-readiness/<release-id>" bash ops/scripts/compliance-snapshot.sh <env>`

---

## E) Where This Fits in Promotion Flow (No automation)

Positioning:
- Dev validates new template version first (build → upload template → dev apply → bootstrap → harden → smoke).
- Pre-release readiness audit is the last checkpoint **before promoting prod**.
- Promotion remains Git-driven (template pin change in prod env):
  - Runbook: `OPERATIONS_PROMOTION_FLOW.md`

Audit timing (recommended):
1. Open promotion PR for prod template pin.
2. Generate readiness packet for the exact commit under review (attach to PR/record externally).
3. Human Go/No-Go sign-off.
4. Proceed with the explicit prod apply/recreate + bootstrap + harden.

---

## F) Optional Helper (Safe, Read-only by default)

To scaffold a readiness packet directory (no signing, no network calls):
```bash
bash ops/scripts/pre-release-readiness.sh <release-id> <env>
```

This helper:
- finds latest local compliance snapshot and drift audit (if present)
- writes a checklist skeleton with pre-filled evidence references
- writes a derived `manifest.sha256` for the readiness packet
