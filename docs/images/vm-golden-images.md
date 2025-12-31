# VM Golden Images (Contracts Only)

Samakia Fabric treats VM images as **immutable artifacts** governed by contracts.

Operator commands live in `../operator/cookbook.md`.

## Canonical reference

A VM image is uniquely referenced by:
- `storage_path`
- `sha256`

These values live in `contracts/images/vm/**/image.yml` and must be filled
by operators after build validation.

## Guarded template registration

Phase 8 Part 2 introduces **guarded** Proxmox template registration:

- token-only API (strict TLS)
- explicit operator opt-in (`IMAGE_REGISTER=1`)
- environment allowlist (never prod by default)
- evidence packets per registration

See: `proxmox-template-registration.md`

## Non-scope

- No VM lifecycle management
- No VM creation or scaling
