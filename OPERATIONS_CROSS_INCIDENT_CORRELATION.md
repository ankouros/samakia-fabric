# Cross-Incident Correlation & Analysis (Read-only) — Timeline Stitching + Hypothesis Tracking

This playbook defines a **defensible, evidence-first** cross-incident correlation workflow for Samakia Fabric.

Non-negotiable constraints:
- Evidence is read-only (no remediation, no cleanup, no mutation).
- Original evidence packets are **referenced, never merged** and never copied into a “master evidence” pack.
- Derived artifacts (timelines, hypothesis registers) are separate, clearly marked as derived, and may be signed/dual-signed/TSA-notarized independently.
- Legal hold remains labels-only and independent (`<evidence>/legal-hold/`).
- No root SSH enablement; break-glass remains console-only.

Guiding principle:
Correlation organizes truth. Hypotheses explore it. Evidence remains untouched.

---

## A) Purpose & Non-goals

### What correlation is
- A discipline for **linking related incidents** into a coherent view (assets, time overlap, shared artifacts).
- A method to produce **unified, append-only** timelines that remain traceable to hashed evidence.
- A framework for audit/legal/executive review that keeps facts and hypotheses separate.

### What correlation is not
- Root-cause proof or attribution.
- Detection, enforcement, or remediation.
- “Evidence normalization” that rewrites timestamps or changes content.

Why this exists:
- Repeated S2 events or any S3/S4 often indicate **systemic risk** (control gaps, shared blast radius, repeated operator error, repeated attacker behavior).

---

## B) When to Perform Correlation (Triggers + Authorization)

Perform correlation when:
- Multiple **S2** incidents occur within a short window or share common assets.
- Any **S3/S4** incident occurs.
- A regulator/legal request requires cross-incident linkage.

Authorization model (minimum):
- Incident commander authorizes correlation scope and timeline generation.
- Security lead approves if analysis touches sensitive logs or expands scope.
- Legal authority involvement if the request is legal/regulatory or if policy mandates legal hold.

Legal hold interaction (strict):
- Correlation must not silently broaden scope.
- If correlation expands the incident set or evidence set, **declare/extend legal hold explicitly** on newly in-scope evidence packs.
- Legal hold labels are recorded under each evidence pack: `<evidence_dir>/legal-hold/`.

---

## C) Canonical Timeline Model (UTC-only, event-based)

Timeline entries are **event records** referencing evidence by path + hash, not narrative prose.

Time rule:
- UTC only (`timestamp_utc`).
- Timeline timestamps represent **collection time** unless the entry explicitly cites an in-evidence event timestamp.
- Do not reorder events based on inference.

### Required fields (per entry)
- `timestamp_utc`: ISO-like UTC string (e.g., `2025-12-28T01:02:03Z` or `20251228T010203Z`)
- `incident_id`: incident identifier (e.g., `INC-2025-0007`)
- `evidence_ref`: `relative/path/to/evidence:sha256=<hash>` (hash must be from the evidence `manifest.sha256`)
- `event_type`: one of `auth`, `network`, `config`, `process`, `app`, `package`, `integrity`, `meta`, `other`
- `description`: factual statement (no inference)
- `collector`: tool or operator identity (from evidence metadata where available)
- `confidence`: `high` / `medium` / `low` (confidence in the record, not the hypothesis)

### Prohibited
- Rewriting timestamps to “make the story fit”.
- Inferring ordering without evidence.
- Embedding hypotheses inside timeline entries.

### Recommended formats

CSV (preferred for tooling):
```csv
timestamp_utc,incident_id,evidence_ref,event_type,description,collector,confidence
20251228T010203Z,INC-2025-0007,forensics/INC-2025-0007/snapshot-20251228T010203Z/system/identity.txt:sha256=<...>,meta,Collected artifact: system/identity.txt,collector:<from-metadata>,high
```

Markdown (preferred for human review):
```md
| timestamp_utc | incident_id | event_type | description | evidence_ref | confidence |
|---|---:|---|---|---|---|
| 20251228T010203Z | INC-2025-0007 | meta | Collected artifact: system/identity.txt | forensics/...:sha256=... | high |
```

---

## D) Hypothesis Tracking Model (Separate from Timeline)

Maintain a hypothesis register separate from the timeline.

Hard rules:
- Hypotheses must never be embedded in original evidence or modify evidence files.
- Hypotheses must never be embedded in the timeline as “facts”.
- Rejected hypotheses remain recorded (no deletion).

### Recommended structure: `correlation/<correlation-id>/hypotheses.json`

For each hypothesis:
- `hypothesis_id`: unique ID (e.g., `H-001`)
- `statement`: testable and falsifiable statement
- `status`: `open` | `supported` | `contradicted` | `rejected`
- `supporting_evidence`: list of `evidence_ref`
- `contradicting_evidence`: list of `evidence_ref`
- `review_history`: append-only list of `{timestamp_utc, reviewer, action, notes}`

Template example (minimal):
```json
{
  "correlation_id": "CORR-2025-0002",
  "hypotheses": [
    {
      "hypothesis_id": "H-001",
      "statement": "The same SSH key was added across multiple containers within 15 minutes.",
      "status": "open",
      "supporting_evidence": [],
      "contradicting_evidence": [],
      "review_history": []
    }
  ]
}
```

---

## E) Correlation Workflow (Repeatable, Conservative)

1) Define scope (explicit list)
- List incident IDs in scope and why they are linked.
- Record authorization and any legal involvement.

2) Verify evidence integrity before analysis
- For each evidence pack: verify `manifest.sha256` and detached signature(s).
- If TSA is present: verify timestamp token offline.
- If integrity verification fails: stop and re-collect or escalate.

3) Build unified timeline (append-only)
- Create a new correlation workspace: `correlation/<correlation-id>/`
- Build `timeline.csv` and `timeline.md` referencing existing evidence paths + hashes.
- Do not copy evidence files into correlation workspace.

4) Identify candidate patterns (no inference)
Examples of patterns (still not conclusions):
- Time overlap between incidents
- Same asset(s) repeated (same hostnames, VMIDs, service names)
- Same class of artifact drift (e.g., repeated SSH config changes)

5) Form hypotheses (explicitly labeled)
- Add hypotheses to `hypotheses.json`
- Each hypothesis must be falsifiable and have explicit evidence references.

6) Test hypotheses against evidence
- Add supporting/contradicting evidence refs
- Update status (`open` → `supported`/`contradicted`/`rejected`)
- Record review history (who/when/what changed)

7) Decide outcome
- Close correlation (document why and what remains unknown)
- Escalate severity if the correlation changes risk posture
- Declare systemic issue (control gap), without implying intent or blame

Stop conditions (do not spiral):
- Evidence is insufficient to proceed without expanding scope/authorization.
- Legal constraints require escalation before collecting additional evidence.
- Analysis turns speculative (hypotheses cannot be tested with available evidence).

---

## F) Evidence Reuse & Chain-of-Custody Rules

Strict rules:
- Evidence is **referenced**, never copied.
- Derived artifacts are stored separately and clearly marked as derived:
  - `correlation/<correlation-id>/timeline.csv`
  - `correlation/<correlation-id>/timeline.md`
  - `correlation/<correlation-id>/hypotheses.json`
  - `correlation/<correlation-id>/manifest.sha256`
- Derived artifacts must not modify or invalidate originals.
- If legal hold applies: label each in-scope evidence pack and (optionally) the correlation pack independently.

---

## G) Signing / Dual-control / TSA Notarization (Derived Artifacts)

Policy (typical):
- Internal post-mortem: signing optional.
- Executive review or external audit: signing required.
- Regulator/legal review: signing + dual-control recommended; TSA optional/required per policy.

Rules:
- Signing a correlation pack proves **integrity of analysis artifacts**, not correctness of conclusions.
- Correlation artifacts must remain derived; signatures do not “upgrade” them into original evidence.

Procedure (reuses existing tooling):
```bash
# Build correlation artifacts first (manifest.sha256 must exist).
export COMPLIANCE_SNAPSHOT_DIR="correlation/<correlation-id>"
export COMPLIANCE_GPG_KEY="<FPR>"
bash ops/scripts/compliance-snapshot.sh samakia-prod

# Optional dual-control: create DUAL_CONTROL_REQUIRED + approvals.json in the correlation dir, then:
export COMPLIANCE_GPG_KEYS="<FPR_A>,<FPR_B>"
export ALLOW_PARTIAL_SIGNATURE=1
bash ops/scripts/compliance-snapshot.sh samakia-prod
```

Offline verification:
```bash
bash ops/scripts/verify-compliance-snapshot.sh correlation/<correlation-id>
```

---

## H) Optional Read-only Helper (Timeline Builder)

If you want a deterministic “first draft” timeline from existing evidence manifests:
- `bash ops/scripts/correlation-timeline-builder.sh <correlation-id> <evidence_dir...>`

This helper:
- reads `manifest.sha256` + `metadata.json` (timestamps only) from evidence packs
- outputs `correlation/<correlation-id>/timeline.csv` and `timeline.md`
- produces a derived `manifest.sha256` for the correlation pack
- does not sign, does not notarize, and does not modify evidence
