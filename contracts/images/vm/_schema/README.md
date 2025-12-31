# VM Image Contract Schema

This schema defines the **VmImageContract** used to describe VM golden images
as immutable artifacts. The canonical reference is:

- `spec.artifact.storage_path`
- `spec.artifact.sha256`

Contracts are **validate-only** in Phase 8. No VM lifecycle management is implied.

## Notes

- `storage_path` and `sha256` are placeholders in example contracts and must be
  filled by operators at build time.
- Evidence packets are required for build/validation and are never committed.
