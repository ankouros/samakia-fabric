# VM Image Lifecycle

Phase 8 Part 1 provides a **guarded local build pipeline** and validate-only acceptance.
Phase 8 Part 2 adds **guarded template registration** (token-only; explicit opt-in).
Operator commands live in `../operator/cookbook.md`.

## Steps (design)

1. Build with Packer + Ansible (idempotent, guarded via `IMAGE_BUILD=1`)
2. Validate image (qcow2 format + offline posture checks)
3. Compute `sha256`
4. Update contract with `storage_path` + `sha256`
5. Generate evidence packet (not committed)
6. Optional: register as Proxmox template (guarded; token-only; evidence required)

Reproducibility rules:
- Base images must be pinned by digest (no floating tags).
- APT sources must use a snapshot mirror during build.
- Each image must include `/etc/samakia-image-version` with build metadata.

## Evidence packets

Stored under `evidence/images/<name>/<version>/<UTC>/` and include:
- build manifest
- sha256 checksum
- acceptance logs
