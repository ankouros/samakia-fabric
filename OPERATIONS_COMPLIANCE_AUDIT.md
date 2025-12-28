# Compliance Snapshots & Signed Audit Exports

This runbook defines how to produce **immutable, timestamped compliance snapshots** and **cryptographically sign** them for offline verification.

Scope (by design):
- Evidence generation only (read-only).
- No auto-remediation.
- No implicit `terraform apply`.
- No secrets/tokens are written into snapshot artifacts.

---

## 1) What a compliance snapshot is

A compliance snapshot is a directory containing:
- Terraform drift output (`terraform plan`, no apply).
- Ansible drift output (`harden.yml` in `--check --diff` mode).
- Environment metadata (env name, pinned template version, Git commit, timestamp UTC).
- Tool versions (Terraform/Ansible/Python/GPG).
- A deterministic checksum manifest (`manifest.sha256`) and a detached signature (`manifest.sha256.asc`).

This substrate evidence can be complemented with **application-level evidence bundles** (per service) that follow the same signing/notarization model.

See:
- `OPERATIONS_APPLICATION_COMPLIANCE.md`
- `COMPLIANCE_EVIDENCE_MODEL.md`

For cross-incident analysis, create **derived correlation artifacts** (timelines + hypothesis register) that reference evidence packs by path+hash; derived artifacts may be signed/notarized separately:
- `OPERATIONS_CROSS_INCIDENT_CORRELATION.md`

For incidents, produce a separate **forensics packet** (facts-only) that is also signable/notarizable:
- `OPERATIONS_POST_INCIDENT_FORENSICS.md`
- `COMPLIANCE_FORENSICS_EVIDENCE_MODEL.md`

Severity (S0–S4) determines **evidence depth** and cryptographic requirements (signing/dual-control/TSA), not remediation:
- `INCIDENT_SEVERITY_TAXONOMY.md`

Snapshots are:
- Immutable (written once, then marked read-only).
- Verifiable offline (checksum + signature).
- Environment-scoped (`dev` vs `prod` are separate).

---

## 2) Prerequisites (runner host)

Must be true on the host where you run audits:
- Proxmox API TLS is trusted via the host trust store (internal CA installed).
- Proxmox API token env vars are present:
  - `TF_VAR_pm_api_url`
  - `TF_VAR_pm_api_token_id`
  - `TF_VAR_pm_api_token_secret`
- GPG is installed and you have access to a signing key locally (private key never leaves your secure key storage).

---

## 3) GPG key management (operator-owned)

Do not generate or store keys in Git.

### Create a signing key (one-time, operator workstation)
Example (interactive):
```bash
gpg --full-generate-key
gpg --list-secret-keys --keyid-format=long
```

Export the public key for auditors/verification (safe):
```bash
gpg --armor --export <KEY_FINGERPRINT> > signer-publickey.asc
```

### Rotation policy (recommended)
- Rotate on a schedule (e.g. yearly) or after suspected compromise.
- Keep old public keys to verify historical snapshots.
- Never re-sign old snapshots unless explicitly required by policy.

---

## 4) Generate a signed compliance snapshot (read-only)

Run from the repo root on the runner host.

Required env:
- `TF_VAR_pm_api_url`
- `TF_VAR_pm_api_token_id` (contains `!`; quote it)
- `TF_VAR_pm_api_token_secret`
- `COMPLIANCE_GPG_KEY` (fingerprint or key id)

Command:
```bash
bash ops/scripts/compliance-snapshot.sh samakia-prod
```

Output location (ignored by Git):
- `compliance/<env>/snapshot-<UTC>/`

Hard rule:
- Snapshots should be generated from a clean Git working tree (the script fails if dirty unless `ALLOW_DIRTY_GIT=1` is set).

---

## 4.1) Dual-control (two-person) signing

For compliance contexts that require a two-person rule, use dual-control signing:
- Two independent detached signatures are required: `manifest.sha256.asc.a` and `manifest.sha256.asc.b`
- Verification enforces dual signatures when `DUAL_CONTROL_REQUIRED` is present

Runbook:
- `OPERATIONS_KEY_CUSTODY_DUAL_CONTROL.md`

---

## 5) Verify a snapshot (offline-capable)

Verification validates:
- Integrity (all file checksums match the manifest)
- Authenticity (manifest signature matches the signer key)

Command:
```bash
bash ops/scripts/verify-compliance-snapshot.sh compliance/samakia-prod/snapshot-<UTC>
```

Notes:
- The snapshot includes `signer-publickey.asc` for offline verification.
- Verification runs with an isolated temporary GPG home (does not mutate your global keyring).

---

## 5.1) Timestamp notarization (RFC 3161)

If a snapshot contains `manifest.sha256.tsr`, verification also validates the TSA token offline and prints the TSA timestamp.

Runbook:
- `OPERATIONS_EVIDENCE_NOTARIZATION.md`

---

## 6) Retention & export policy (manual, no automation)

Storage:
- Snapshots are local artifacts by default and must not be committed automatically.
- Export manually to your organization’s artifact storage or cold storage, according to policy.

Legal hold:
- If a snapshot is in-scope for legal hold, apply non-destructive labels under `<snapshot>/legal-hold/` and sign/notarize that label pack separately.
- See `OPERATIONS_LEGAL_HOLD_RETENTION.md` and `LEGAL_HOLD_RETENTION_POLICY.md`.

Suggested retention (tune to your policy):
- Daily snapshots: keep 30 days
- Monthly snapshots: keep 12 months
- Incident snapshots: keep per incident policy

Explicitly not stored:
- API tokens, passwords, private keys, SSH private keys

---

## 7) What to do when drift is detected

This system detects drift; it does not fix it.

- Terraform drift: remediate via Git change + explicit `terraform apply` (or rebuild/recreate), never by manual edits.
- Ansible drift: remediate via Ansible changes + deliberate re-run of `harden.yml` (non-check mode) with human approval.
