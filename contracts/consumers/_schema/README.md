# Consumer Contract Schema

This directory defines the canonical schema for **Phase 6 consumer contracts**.

Notes:
- Contract files are stored as `.yml`, but are **JSON-compatible** to allow
  validation with the standard Python `json` module (no external dependencies).
- The schema is intentionally minimal and stable; new consumer types can be
  added without breaking existing contracts by using `spec.type = custom`.

Validation is performed by:
- `ops/scripts/phase6-entry-check.sh`
