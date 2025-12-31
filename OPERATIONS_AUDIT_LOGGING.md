# Operations — Audit Logging Baseline

This runbook defines the **minimum viable audit trail** for Samakia Fabric.

Scope:
- Infrastructure operations
- Control-plane services
- Incident response evidence

## Required log sources

### SSH and authentication
- `/var/log/auth.log` (or `journalctl -u ssh`)
- Failed logins and key-based auth events

### Privileged commands
- `sudo` entries in auth logs
- Use `journalctl` or `/var/log/auth.log` depending on distro

### Service logs
- systemd journals per service unit:
  - `journalctl -u <service>`

## Retention guidance

- Local retention: **7 days** minimum
- Evidence retention: **30 days** minimum, exported and signed if required
- Longer retention may be required for legal hold or compliance

## Evidence export (read-only)

1) Collect logs with read-only commands.
2) Store under `evidence/<category>/<UTC>/`.
3) Generate `manifest.sha256` for integrity.
4) Sign or notarize if required by policy.

## Redaction rules

- Do **not** include tokens, credentials, or secrets.
- Redact sensitive fields before packaging evidence.

## References

- `OPERATIONS_COMPLIANCE_AUDIT.md`
- `OPERATIONS_POST_INCIDENT_FORENSICS.md`
- `LEGAL_HOLD_RETENTION_POLICY.md`
