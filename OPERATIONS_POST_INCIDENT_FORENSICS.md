# Post-Incident Forensics (Read-only) — Evidence Collection & Preservation

This runbook defines a **read-only, auditor-grade** post-incident forensics workflow for Samakia Fabric.

Non-negotiable constraints:
- No infrastructure mutation, no remediation, no `terraform apply`
- No root SSH enablement (break-glass remains console-only)
- Strict TLS model unchanged; no insecure flags
- Evidence may be signed (single/dual-control) and optionally TSA-notarized
- No secrets/tokens stored in Git or inside evidence artifacts

Guiding principle:
Forensics preserves truth. Remediation rebuilds systems.

---

## A) Scope & Principles

### What forensics is
- Fact collection and preservation
- Timeline reconstruction based on collected artifacts
- Chain-of-custody tracking and evidence integrity

### What forensics is not
- Remediation or “cleanup”
- Ad-hoc hunting that changes systems
- Policy decisions (legal/HR approvals are out-of-band)

### Legal/HR boundary notes
- Logs and process output may contain PII or sensitive content.
- Collect only what is authorized and necessary.
- If you suspect data exposure, pause and follow your organization’s legal/IR procedure.

---

## B) Incident Classification & Trigger

Typical triggers for a forensics packet:
- Authentication anomalies (unexpected logins, new keys, sudo spikes)
- Integrity drift suspected (unexpected config changes)
- Unexpected network exposure (new listeners, unexpected outbound)
- Suspected data exposure (requires explicit authorization)
- HA-related incidents with unclear cause (node failover, split-brain symptoms)

Authorization model (minimum):
- Incident commander authorizes evidence collection
- Security lead approves scope if logs may include sensitive content
- Collector records “who authorized” in metadata

Guidance: snapshot vs power down (do not automate)
- If the system is actively being tampered with: prioritize **preservation** and **containment**.
- If evidence collection requires higher volatility order (memory): plan explicitly; do not improvise.

---

## C) Evidence Preservation Checklist

Before collecting:
- Confirm UTC time and time sync status
- Record who is collecting, from where, and why
- Minimize changes:
  - Do not restart services
  - Do not install packages
  - Prefer command outputs over file edits

Order of volatility (documented guidance):
1. Memory / volatile runtime state (processes, network sockets)
2. Logs (journald/auth logs)
3. Disk artifacts (file hashes, package lists)
4. Infrastructure metadata (Terraform plans, inventory)

Use copies, not originals:
- Prefer “copy-out” of command outputs to evidence directory
- Avoid copying sensitive files; collect hashes instead

---

## C.1) Severity-Driven Evidence Collection

Evidence depth must be proportional to severity (do not over-collect).

Policy source:
- `INCIDENT_SEVERITY_TAXONOMY.md`

### Decision flow (03:00-safe)

1) Classify severity (S0–S4)
- Use the definitions and examples in `INCIDENT_SEVERITY_TAXONOMY.md`.
- If unsure between two levels: choose the higher level *only if* it changes required approvals (don’t escalate by panic).

2) Verify authorization before collecting logs
- S0/S1: proceed with minimal notes only (avoid packets).
- S2: incident commander approves scope; security consulted if logs may include sensitive data.
- S3/S4: security lead approves scope; legal/HR per policy if data exposure suspected.

3) Collect evidence by category per severity
- Follow the evidence depth matrix in `INCIDENT_SEVERITY_TAXONOMY.md`.
- Default: collect **system/process/network + safe hashes** first.
- Auth/security logs are collected only when severity requires it and scope is approved.

4) Package evidence deterministically
- One snapshot directory per collection run: `forensics/<incident-id>/snapshot-<UTC>/`
- Produce `manifest.sha256` last.
- After `manifest.sha256` exists: add only detached signatures/TSA token; do not modify evidence files.

5) Apply cryptographic requirements (by severity)
- S0: no signing (no packet).
- S1: signing optional.
- S2: signing required; dual-control/TSA optional.
- S3: signing required; dual-control required; TSA optional.
- S4: signing required; dual-control required; TSA required.

6) Escalate severity when triggers appear
Escalate to the next severity if any of these appear:
- unexpected successful authentication
- unauthorized sudo activity
- persistence indicators
- evidence of data access/exfiltration
- multi-node / cluster control-plane concerns

### “Do not over-collect” guidance

Avoid:
- copying whole logs when targeted filters are sufficient
- collecting broad disk content “just in case”
- collecting PII unless explicitly authorized

Collect the minimum that can later justify:
- what happened
- who authorized scope
- what was and was not collected

---

## D) Evidence Collection Steps (LXC + Host Runner)

Collection channels (allowed):
- `ssh samakia@<ip>` (preferred; read-only)
- Proxmox console for the CT (break-glass channel; root inside CT is allowed only via console)
- Proxmox node shell (`pct enter <vmid>`) if you have node access

Never:
- Enable root SSH
- Use insecure TLS flags
- Collect secrets/credentials

### Minimal evidence set (per affected container)

System identity & time:
- `hostname`
- UTC time: `date -u`
- uptime: `uptime -p` (or `uptime`)
- OS: `cat /etc/os-release`
- kernel: `uname -a`

Process & user context (read-only):
- `ps auxww`
- `who -a`
- `id`
- `last -n 50` (if available; may not exist in minimal containers)

Network state (read-only):
- `ip a`
- `ip r`
- `ss -tulpen` (may require privileges; collect what is available)

Auth & security logs (minimize scope; redaction policy applies):
- `journalctl --no-pager -u ssh -n 500` (if journald present)
- `journalctl --no-pager _COMM=sudo -n 200`
- If file logs exist: `/var/log/auth.log` tail (Ubuntu may be journald-only)

File integrity signals (hashes only; do not copy secrets):
- `sha256sum` of:
  - `/etc/ssh/sshd_config` (if present)
  - `/etc/passwd`, `/etc/group`
  - `/etc/sudoers` and `/etc/sudoers.d/*` (if present)

Package state:
- `dpkg -l` (or `apt list --installed` if available)

Application evidence pointers (do not collect secrets):
- service version/build ID (if available)
- log locations (paths only; do not copy logs unless authorized)
- config fingerprint allowlist (hashes of non-secret configs)

### Optional helper (read-only)

If safe and authorized, run the local collector on the target (inside CT or on host):
```bash
bash ops/scripts/forensics-collect.sh <incident-id> --env <env> --scope lxc
```

This produces a deterministic evidence directory with a checksum manifest. It does not sign.

---

## E) Evidence Packaging (Directory Structure)

Recommended structure:
```text
forensics/
  <incident-id>/
    snapshot-<UTC>/
      metadata.json
      timeline.txt
      system/
      network/
      logs/
      packages/
      integrity/
      apps/
      manifest.sha256
      # Detached signatures (optional)
      manifest.sha256.asc
      # Dual-control (optional)
      DUAL_CONTROL_REQUIRED
      approvals.json
      manifest.sha256.asc.a
      manifest.sha256.asc.b
      signer-publickey.a.asc
      signer-publickey.b.asc
      # TSA notarization (optional)
      manifest.sha256.tsr
      tsa-metadata.json
      tsa-ca.pem
      # Legal hold labels (optional; excluded from evidence manifest)
      legal-hold/
        LEGAL_HOLD
        hold.json
        evidence-manifest.sha256sum
        manifest.sha256
        manifest.sha256.asc
```

Determinism:
- Use UTC timestamps
- Sort file lists before hashing
- Hash outputs, do not edit them after manifest creation

Legal hold:
- If policy requires legal hold for this incident (commonly S3/S4), add a label pack under `<snapshot>/legal-hold/` and sign it separately (labels are excluded from the evidence manifest by design).
- See `OPERATIONS_LEGAL_HOLD_RETENTION.md`.

Redaction policy:
- Default to minimal logs and process output.
- Do not include raw secrets or tokens.
- If logs contain sensitive material, store them under strict access controls and record the scope decision in `metadata.json`.

---

## F) Signing, Dual-Control & Notarization

Forensics bundles reuse the **same signing model** as compliance snapshots:
- Integrity target: `manifest.sha256`
- Detached signatures (single or dual-control)
- Optional TSA timestamp token (RFC 3161)

### Single signature
```bash
export COMPLIANCE_SNAPSHOT_DIR="forensics/<incident-id>/snapshot-<UTC>"
export COMPLIANCE_GPG_KEY="<FPR>"

bash ops/scripts/compliance-snapshot.sh <env>
```

### Dual-control (two-person)
Create `DUAL_CONTROL_REQUIRED` and `approvals.json` (see `OPERATIONS_KEY_CUSTODY_DUAL_CONTROL.md`), then collect both signatures:
```bash
export COMPLIANCE_SNAPSHOT_DIR="forensics/<incident-id>/snapshot-<UTC>"
export COMPLIANCE_GPG_KEYS="<FPR_A>,<FPR_B>"
export ALLOW_PARTIAL_SIGNATURE=1

bash ops/scripts/compliance-snapshot.sh <env>
```

### Optional TSA notarization
```bash
export COMPLIANCE_TSA_URL="https://tsa.example.org/tsa"
export COMPLIANCE_TSA_CA="/path/to/tsa-ca-bundle.pem"

bash ops/scripts/compliance-snapshot.sh <env>
```

### Offline verification
```bash
bash ops/scripts/verify-compliance-snapshot.sh forensics/<incident-id>/snapshot-<UTC>
```

---

## G) Analysis Notes & Conclusions (Separation of concerns)

Record findings in two tracks:
- Facts: what was observed (hashes, timestamps, log lines)
- Hypotheses: what might explain facts (clearly labeled)

Do not modify evidence files during analysis.
Instead, add:
- `analysis-notes.md` (separate, unsigned if it contains opinions)
- references to evidence file paths and checksums

---

## Cross-Incident Correlation (derived artifacts)

When incidents repeat (multiple S2) or any S3/S4 occurs, create a **separate correlation workspace** that references (does not copy) evidence packs:
- unified, append-only timeline (facts only)
- hypothesis register (explicitly separated from facts)
- optional signing/dual-control/TSA notarization for analysis artifacts (integrity only; does not prove correctness of conclusions)

Runbook:
- `OPERATIONS_CROSS_INCIDENT_CORRELATION.md`

---

## H) Handover to Remediation

Handover packet should include:
- signed forensics bundle directory
- summary of confirmed facts
- scope and authorization record
- recommended rebuild/remediation actions (as separate plan, not evidence)

Retention guidance (policy-defined):
- short-term hot storage for active investigation
- long-term cold storage for audit retention

Rebuild-over-repair remains the default.
