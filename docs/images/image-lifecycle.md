# VM Image Lifecycle

This is a **design-only** lifecycle. No builds are executed in Phase 8.

## Steps (design)

1. Build with Packer + Ansible (idempotent)
2. Validate image (boot, cloud-init, SSH, logging)
3. Compute `sha256`
4. Update contract with `storage_path` + `sha256`
5. Generate evidence packet (not committed)

## Evidence packets

Stored under `evidence/images/<name>/<version>/<UTC>/` and include:
- build manifest
- sha256 checksum
- acceptance logs
