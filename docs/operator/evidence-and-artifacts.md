# Evidence and Artifacts

## Locations (gitignored)

- `evidence/` — evidence packets from audits, validations, and runbooks
- `artifacts/` — operator-generated bundles and intermediate outputs
- `audit/` — runtime checks and guard reports
- `evidence/INDEX.md` and `evidence/index.json` are tracked as deterministic indexes.

## Evidence packet structure

Typical packet structure:

```
<root>/report.md
<root>/metadata.json
<root>/manifest.sha256
<root>/manifest.sha256.asc (optional)
```

## Rules

- Never commit evidence packets or artifacts
- Only the evidence indexes are tracked
- Never include secrets or tokens in reports
- Prefer redaction for identifiers that might leak access details
