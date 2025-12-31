# VM Image Lifecycle

Phase 8 Part 1 provides a **guarded local build pipeline** and validate-only acceptance.
No Proxmox registration or VM provisioning occurs in this phase.

## Steps (design)

1. Build with Packer + Ansible (idempotent, guarded via `IMAGE_BUILD=1`)
2. Validate image (qcow2 format + offline posture checks)
3. Compute `sha256`
4. Update contract with `storage_path` + `sha256`
5. Generate evidence packet (not committed)

## Evidence packets

Stored under `evidence/images/<name>/<version>/<UTC>/` and include:
- build manifest
- sha256 checksum
- acceptance logs
