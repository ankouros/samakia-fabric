# Evidence Notarization (RFC 3161 TSA) — Trusted Timestamping

This runbook adds **time-of-existence proof** for compliance snapshots using an RFC 3161 **Trusted Timestamp Authority (TSA)**.

Scope (non-negotiable):
- Snapshots remain read-only evidence (no remediation, no `terraform apply`).
- TSA notarization is **optional** and **opt-in**.
- TSA does not replace signer authority; it only proves the snapshot existed **at or before** the TSA timestamp.
- Offline verification must remain possible.

---

## 1) Notarization model (contract)

### What is notarized
- The notarization target is `manifest.sha256`.
- The TSA timestamp token is stored as `manifest.sha256.tsr`.

### When notarization happens
- Notarization occurs **after** the snapshot is complete and **after** required signature(s) exist:
  - Single-signature snapshots: after `manifest.sha256.asc`
  - Dual-control snapshots: after `manifest.sha256.asc.a` and `manifest.sha256.asc.b`

### What notarization proves (and does not)
TSA proves:
- The snapshot’s manifest existed **at or before** the TSA’s signed timestamp.

TSA does not prove:
- Correctness of the environment
- Authorization/approval
- Absence of drift

TSA ≠ signer. TSA ≠ governance.

---

## 2) Enabling TSA notarization (opt-in)

TSA notarization is enabled only when these env vars are set:
- `COMPLIANCE_TSA_URL` (must be `https://...`)
- `COMPLIANCE_TSA_CA` (path to a trusted TSA CA bundle used for strict TLS and offline verification)

Optional:
- `COMPLIANCE_TSA_POLICY` (policy OID, if your TSA requires it)

Example:
```bash
export COMPLIANCE_TSA_URL="https://tsa.example.org/tsa"
export COMPLIANCE_TSA_CA="/path/to/tsa-ca-bundle.pem"

bash ops/scripts/compliance-snapshot.sh samakia-prod
```

Artifacts written (when enabled):
- `manifest.sha256.tsr`
- `tsa-metadata.json`
- `tsa-ca.pem` (public trust bundle copied into the snapshot for offline verification)

Strict TLS:
- The TSA request uses `curl --cacert ...` and refuses non-HTTPS URLs.
- No insecure flags are supported.

Failure behavior:
- TSA failure exits non-zero and writes `TSA_NOTARIZATION_FAILED`.
- The snapshot and existing signatures remain valid and unchanged.

---

## 3) Offline verification (auditor workflow)

Verification order:
1. `sha256sum -c manifest.sha256` (integrity of evidence files)
2. Signature verification (single or dual-control)
3. TSA verification (if `manifest.sha256.tsr` exists)

Scripted:
```bash
bash ops/scripts/verify-compliance-snapshot.sh compliance/<env>/snapshot-<UTC>
```

TSA trust input:
- Preferred: the snapshot contains `tsa-ca.pem`
- Alternatively: set `COMPLIANCE_TSA_CA=/path/to/tsa-ca-bundle.pem` during verification

What “OK” means:
- TSA token signature validates against the pinned CA
- TSA token matches `manifest.sha256`
- Timestamp is displayed and can be recorded as evidence

---

## 4) TSA trust & custody

### Public TSA (commercial)
- Use a vendor-provided TSA endpoint and vendor CA bundle.
- Pin trust via `COMPLIANCE_TSA_CA` (do not rely on “system CAs” by default unless policy explicitly allows it).

### Internal TSA (optional)
- Use an internal CA and an internal TSA endpoint.
- Maintain a controlled CA distribution process (pinning is mandatory).

### Policy OIDs
If your TSA requires a policy OID:
- Set `COMPLIANCE_TSA_POLICY` to the required OID.
- Record the policy in `tsa-metadata.json` as part of the evidence.

---

## 5) Operational guidance (when to require TSA)

Recommended:
- Production monthly evidence exports: TSA enabled
- Incident snapshots: TSA enabled when available

Optional:
- Developer/local snapshots: TSA typically disabled

If TSA is unavailable:
- Do not “fake” timestamps.
- Use signed snapshots without TSA and document the exception; re-run with TSA when available if policy requires it.
