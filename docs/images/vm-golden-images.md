# VM Golden Images (Contracts Only)

Samakia Fabric treats VM images as **immutable artifacts** governed by contracts.

## Canonical reference

A VM image is uniquely referenced by:
- `storage_path`
- `sha256`

These values live in `contracts/images/vm/**/image.yml` and must be filled
by operators after build validation.

## Non-scope

- No VM lifecycle management
- No VM creation or scaling
- No automated registration as Proxmox templates (future guarded phase)
