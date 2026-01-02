# Change Window and Signing

Production exposure requires **both** an approved change window and signed
evidence/approvals. These are hard gates; failure to provide them blocks
execution.

## Change Windows

- Change windows define **start** and **end** times for exposure.
- Windows must be documented in the approval artifact and revalidated at apply.
- Expired or malformed windows are rejected.
- Use `CHANGE_WINDOW_START` and `CHANGE_WINDOW_END` in apply/rollback commands.

## Signing

- Prod approvals and evidence are signed when signing is configured.
- Signing references are stored as `signature_ref` values (no private keys in Git).
- Evidence packets include detached signatures (for example, `manifest.sha256.asc`).
- Set `EXPOSE_SIGN=1` and `EVIDENCE_SIGN_KEY=<gpg-id>` for prod apply/rollback.

## Operator Expectations

- Maintain signing keys **outside the repository**.
- Verify signatures before apply and after evidence generation.
- Record change window IDs and approvals with the evidence packet.

See `docs/operator/exposure.md` for command sequences.
