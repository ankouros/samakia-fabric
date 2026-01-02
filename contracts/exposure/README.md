# Exposure Contracts

This directory defines the contracts and templates that govern **workload exposure**.
Exposure means generating consumer-ready connection artifacts for workloads that
already have bindings. Exposure does **not** provision substrate resources and
does **not** materialize secrets.

## Files

- `exposure-policy.schema.json`: Schema for exposure policy allowlists and invariants.
- `exposure-policy.yml`: Default policy (dev/shared allowlisted; prod restricted).
- `exposure-policy.prod.yml.example`: Example policy for prod (signing + change window).
- `approval.schema.json`: Schema for operator approval artifacts.
- `approval.yml.example`: Example approval artifact (non-prod default).
- `rollback.schema.json`: Schema for rollback intent + verification.
- `rollback.yml.example`: Example rollback artifact.

## Rules

- No secrets are stored in these files.
- TLS is mandatory; plaintext endpoints are forbidden.
- Prod exposure requires signing and a change window.
- Exposure artifacts are written to `artifacts/` and evidence to `evidence/` (gitignored).

See also:
- `docs/operator/exposure.md`
- `docs/exposure/semantics.md`
- `docs/exposure/change-window-and-signing.md`
- `docs/exposure/rollback.md`
