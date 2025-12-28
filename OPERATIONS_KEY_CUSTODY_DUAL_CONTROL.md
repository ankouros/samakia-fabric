# Key Custody & Dual-Control Signing (Two-Person Rule)

This runbook defines governance for **dual-control (two-person rule) signing** of compliance snapshots produced by Samakia Fabric.

Scope:
- Signing governance only (no infrastructure changes).
- Snapshots remain read-only evidence (no remediation, no `terraform apply`).
- Private keys are never stored in Git and never embedded into snapshot artifacts.

---

## A) Roles & Trust Model

### Roles

**Custodian A**
- Holds private signing key A (ideally on hardware token/smartcard).
- Produces signature file `manifest.sha256.asc.a`.
- Must not share private key material or passphrases.

**Custodian B**
- Holds private signing key B (ideally on hardware token/smartcard).
- Produces signature file `manifest.sha256.asc.b`.
- Must not share private key material or passphrases.

**Operator / Runner**
- Generates the snapshot and its `manifest.sha256`.
- May be one of the custodians, but dual-control requires two independent signatures.
- Must not modify snapshot contents after `manifest.sha256` exists (except adding signature files).

**Auditor / Verifier**
- Verifies integrity (`manifest.sha256`) and authenticity (both signatures).
- Validates signer identities via fingerprints and approved public keys.

### Trust boundaries / least privilege
- Custodians need **only** access to the snapshot directory (or exported archive) and their signing capability.
- Operators need Proxmox API read access (token) and SSH access as `samakia` for check-only Ansible drift.
- Auditors need only snapshot exports + trusted public keys (offline capable).

Never do:
- Never store private keys in Git.
- Never sign snapshots generated from an unknown/dirty Git state unless explicitly approved as an exception.
- Never re-run “generation” on an already published snapshot (a new timestamped snapshot must be created).

---

## B) Two-Person Workflow (Step-by-step)

Samakia Fabric treats a snapshot as **compliant only if** it has:
- `manifest.sha256` (integrity manifest), and
- `DUAL_CONTROL_REQUIRED` marker, and
- `manifest.sha256.asc.a` signature, and
- `manifest.sha256.asc.b` signature, and
- public keys for offline verification (`signer-publickey.a.asc`, `signer-publickey.b.asc`)

### 1) Generate snapshot (dual-control required)

Run on the runner host (read-only audit):
```bash
export COMPLIANCE_DUAL_CONTROL=1
export COMPLIANCE_GPG_KEYS="<FPR_A>,<FPR_B>"
export ALLOW_PARTIAL_SIGNATURE=1

bash ops/scripts/compliance-snapshot.sh samakia-prod
```

Expected output directory:
- `compliance/samakia-prod/snapshot-<UTC>/`

Files created (minimum):
- `metadata.json`
- `terraform-plan.txt`, `terraform-plan.json`
- `ansible-check.diff`
- `versions.txt`
- `DUAL_CONTROL_REQUIRED`
- `approvals.json` (declares required signers by fingerprint)
- `manifest.sha256`

Notes:
- If the runner host has neither private key, this produces an **unsigned** snapshot ready for custodians.
- If it has one key, it may produce a **partial** signature; that is acceptable only as a staged workflow.
- Adding signature files later does not invalidate existing signatures because signatures cover the manifest, and the manifest intentionally excludes signature files.

### 2) Custodian A signs (detached)

Custodian A receives the snapshot directory (secure channel / artifact store / removable media).
Custodian A signs the existing manifest:
```bash
export COMPLIANCE_DUAL_CONTROL=1
export COMPLIANCE_GPG_KEYS="<FPR_A>,<FPR_B>"
export ALLOW_PARTIAL_SIGNATURE=1
export COMPLIANCE_SNAPSHOT_DIR="compliance/samakia-prod/snapshot-<UTC>"

bash ops/scripts/compliance-snapshot.sh samakia-prod
```

Expected new file:
- `manifest.sha256.asc.a`

### 3) Custodian B signs (detached)

Custodian B repeats the same “sign-only” step:
```bash
export COMPLIANCE_DUAL_CONTROL=1
export COMPLIANCE_GPG_KEYS="<FPR_A>,<FPR_B>"
export ALLOW_PARTIAL_SIGNATURE=1
export COMPLIANCE_SNAPSHOT_DIR="compliance/samakia-prod/snapshot-<UTC>"

bash ops/scripts/compliance-snapshot.sh samakia-prod
```

Expected new file:
- `manifest.sha256.asc.b`

### 4) Snapshot is compliant only when both signatures verify

Verification (offline-capable):
```bash
bash ops/scripts/verify-compliance-snapshot.sh compliance/samakia-prod/snapshot-<UTC>
```

Fail conditions:
- Missing one of the signature files (`.asc.a` / `.asc.b`)
- Any signature fails verification
- Any file checksum fails (`sha256sum -c`)

---

## C) Key Generation, Storage & Custody

### Recommended key storage
Preferred:
- Hardware-backed keys (smartcard/YubiKey with GPG), with PIN and admin controls.

Acceptable (if hardware is not available):
- Encrypted local GPG keyring on a disk-encrypted device.
- Strong passphrase policy; screen lock; no remote shell exposure.

### Key generation (GPG)
Generate keys interactively (custodian workstation):
```bash
gpg --full-generate-key
gpg --list-secret-keys --keyid-format=long
```

Public key export (shareable):
```bash
gpg --armor --export <FPR> > signer-publickey.<role>.asc
```

Never:
- Never export or share private keys.
- Never store passphrases in shell history or dotfiles.

### Backup policy
- Back up private keys only if required by policy, and only in encrypted form.
- Backups must be stored separately per custodian (no single location that compromises both).

---

## D) Key Rotation & Revocation

### Rotation policy (recommended)
- Rotate signing keys on a fixed cadence (e.g. yearly) or after staff changes.
- Keep old public keys for verification of historical snapshots.

### Revocation
- Maintain a revocation certificate per key.
- Auditors should treat:
  - snapshots signed *before* revocation as valid evidence (depending on policy),
  - snapshots signed *after* revocation as invalid.

### Public key distribution
- Maintain an approved public key list (fingerprints) out-of-band (policy repo, GRC system, or audited document).
- Snapshots include exported public keys to support offline verification, but auditors must still confirm provenance (fingerprint matches approved list).

---

## E) Emergency Procedures

### If a custodian is unavailable
Default: do not “work around” dual control silently.

Options (policy-driven):
- Delay snapshot completion until both custodians are available.
- Use a formally approved alternate custodian key (pre-provisioned), and record the exception.

### Break-glass signing policy (still auditable)
If policy allows a temporary exception:
- Require written approval (ticket/incident record).
- Record:
  - who authorized
  - which snapshot
  - why dual control was not possible
  - which key(s) were used
- Produce a new snapshot if the integrity of custody is in doubt.

Never:
- Never re-enable root SSH or weaken infrastructure security to “get evidence”.

---

## F) Offline Verification Procedure (Auditor)

An auditor verifies, offline:
1. `manifest.sha256.asc.a` verifies against `manifest.sha256`
2. `manifest.sha256.asc.b` verifies against `manifest.sha256`
3. `sha256sum -c manifest.sha256` succeeds
4. Fingerprints match the approved signer list
5. `metadata.json` matches the declared Git commit and environment

Scripted verification:
```bash
bash ops/scripts/verify-compliance-snapshot.sh compliance/<env>/snapshot-<UTC>
```

Manual spot checks:
- Open `metadata.json` and validate:
  - `git_commit`
  - `template_version` / `template_ref`
  - `signing.required_fingerprints`
  - `proxmox.cluster_name` (non-sensitive identifier)

---

## G) Evidence Retention & Chain-of-Custody

Retention:
- Store snapshots outside Git (artifact storage / cold storage).
- Keep integrity/signature files with the snapshot directory.

Chain-of-custody (recommended, no secrets):
- Record per snapshot:
  - snapshot path / ID
  - UTC timestamp
  - Git commit
  - environment
  - signer fingerprints (A and B)
  - where it was stored
  - any exceptions (break-glass, partial signing windows)

Operational guidance:
- Treat the snapshot directory as immutable after `manifest.sha256` exists.
- Only acceptable post-manifest writes: adding detached signature files.
