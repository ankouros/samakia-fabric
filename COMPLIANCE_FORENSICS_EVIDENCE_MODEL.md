# Forensics Evidence Model (Extension)

This document defines how **post-incident forensics evidence** is packaged so it remains:
- minimal and deterministic
- chain-of-custody friendly
- compatible with existing signing (single/dual-control) and optional TSA notarization

Forensics differs from compliance evidence:
- Compliance evidence answers “are we aligned with declared policy/state?”
- Forensics evidence answers “what happened?” (facts for incident review)

Hard rules:
- Evidence is read-only and must not mutate infrastructure.
- Evidence must not include secrets/tokens.
- Evidence directories are local artifacts (never committed automatically).

---

## 1) Directory structure (recommended)

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
      # Optional detached signatures / TSA artifacts
```

`<UTC>` format:
- `YYYYMMDDTHHMMSSZ`

---

## 2) Required metadata fields (`metadata.json`)

Required:
- `incident_id`
- `timestamp_utc`
- `collector` (human identity; no secrets)
- `environment` (e.g. `samakia-prod`)
- `scope` (e.g. `lxc`, `host-runner`, `proxmox-node`)
- `targets` (hostnames, VMIDs, node names if applicable)
- `authorization` (who approved collection + reference ID, no secrets)

Recommended:
- `time_sync` (what was checked: `date -u`, `timedatectl`, etc.)
- `hashing` (algorithm: sha256)
- `redaction_policy` (what was excluded and why)

Forbidden:
- API tokens, passwords, private keys
- raw secrets in any form

---

## 3) Allowed artifact types

Allowed:
- command outputs (text)
- hashes of critical files (not the files themselves)
- package lists
- minimal logs (scoped and authorized)
- references to external systems (ticket IDs, report IDs)

Forbidden:
- memory dumps unless explicitly authorized and opt-in
- raw credential files (`/etc/shadow`, private keys, `.env`)
- full database dumps unless explicitly authorized (high risk)

---

## 4) Integrity and signing model

Integrity target:
- `manifest.sha256` contains hashes of all evidence files (excluding signature and TSA token files).

Signing:
- Single: `manifest.sha256.asc`
- Dual-control: `manifest.sha256.asc.a` and `manifest.sha256.asc.b` with `DUAL_CONTROL_REQUIRED`

TSA notarization (optional):
- `manifest.sha256.tsr` + `tsa-metadata.json`

Verification is offline-capable using:
- public signer keys
- pinned TSA CA (`tsa-ca.pem` or external pinned path)

---

## 5) Chain-of-custody guidance (process)

Chain-of-custody is a process, not a file:
- Record who collected, where, and under which authorization.
- Record transfers (who moved the evidence, where it was stored).
- Preserve immutability after `manifest.sha256` exists (add only detached signatures/TSA token).
