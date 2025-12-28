# Compliance Evidence Model (Application Overlay)

This document standardizes **how application-level compliance evidence is packaged** so it can be signed (single/dual-control) and optionally TSA-notarized using the existing evidence tooling.

Hard rules:
- Evidence is **read-only** and must not mutate infrastructure or workload configuration.
- Evidence bundles must **never include secrets**.
- Evidence bundles are stored outside Git (`compliance/` is ignored).

---

## 1) Evidence bundle structure

Directory layout (per service, per environment, per snapshot):

```text
compliance/
  <env>/
    app-evidence-<service_name>/
      snapshot-<UTC>/
        metadata.json
        versions.txt
        config-fingerprint.txt
        runtime-checks.txt
        references.txt
        manifest.sha256
        # Optional signing outputs (detached)
        manifest.sha256.asc
        # Optional dual-control signing outputs
        DUAL_CONTROL_REQUIRED
        approvals.json
        manifest.sha256.asc.a
        manifest.sha256.asc.b
        signer-publickey.a.asc
        signer-publickey.b.asc
        # Optional TSA notarization outputs
        manifest.sha256.tsr
        tsa-metadata.json
        tsa-ca.pem
```

`<UTC>` format:
- `YYYYMMDDTHHMMSSZ`

---

## 2) Required files and contents

### `metadata.json` (required)
Must include:
- `timestamp_utc`
- `environment`
- `service.name`
- `service.owner`
- `service.criticality` (e.g. `tier-critical` / `tier-noncritical`)
- `service.data_classification` (e.g. `public/internal/confidential`)
- `service.git_commit` (and/or the monorepo commit)
- `service.version` (if applicable; otherwise `unknown`)
- `inputs` (which files were fingerprinted; relative paths only)

Must not include:
- secrets, tokens, passwords, private keys
- full config contents

### `versions.txt` (required)
Human-readable tool/service versions:
- Git commit(s)
- Build version (if available)
- Tool versions (git, sha256sum, language runtime versions if relevant)

### `config-fingerprint.txt` (required)
Deterministic list of hashes:
- One line per allowlisted config file:
  - `sha256  <relative_path>`

No file contents.

### `runtime-checks.txt` (required)
Read-only checks (no mutations):
- What was checked
- What was observed (sanitized; no secrets)
- If a check cannot be run, record `NOT_RUN` with reason

### `references.txt` (optional)
Pointers to external systems:
- ticket IDs
- artifact IDs
- scan report URLs/IDs (no credentials)
- runbook paths

---

## 3) Allowed vs forbidden content

### Allowed
- hashes, versions, config filenames/paths
- non-sensitive identifiers (service name, commit hash, environment)
- public certificates (NOT private keys)
- policy references and ticket IDs

### Forbidden
- `.env` files (except `.env.example`)
- private keys (forbidden key material markers such as `<PRIVATE KEY MATERIAL — REDACTED / FORBIDDEN IN EVIDENCE>)
- raw secrets in any format (tokens, passwords, API keys)
- Terraform state, tfvars, or any credential material

If evidence needs configuration proof but the file contains secrets:
- create a **redacted** config export for evidence (separate file), and hash that instead.

---

## 4) Signing and notarization model

### Integrity target
- The integrity target is `manifest.sha256`.

### Signing
- Single-signature: `manifest.sha256.asc`
- Dual-control: `manifest.sha256.asc.a` + `manifest.sha256.asc.b` and `DUAL_CONTROL_REQUIRED`

### TSA notarization (optional)
- Token: `manifest.sha256.tsr`
- Metadata: `tsa-metadata.json`
- Trust anchor copied for offline verify: `tsa-ca.pem`

Signing proves *who* approved evidence. TSA proves *when* evidence existed.

---

## 5) Reproducibility and determinism expectations

Evidence generation must be deterministic:
- stable snapshot directory naming (UTC)
- stable hashing order (sorted list)
- stable file selection (explicit allowlist)

Evidence is not required to be bit-identical across runs if the underlying system changed, but the **process** must be repeatable and auditable.
