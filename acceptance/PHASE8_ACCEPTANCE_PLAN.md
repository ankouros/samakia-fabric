# Phase 8 Acceptance Plan — VM Golden Image Contracts (Design Only)

Phase 8 is design-only. No VM builds or registrations occur.

## Read-only validation gates

- Contract schema validation
- Example contract validation
- Documentation presence
- Evidence paths are gitignored

## Optional build gate (future phase)

- Packer build execution
- Ansible hardening idempotency
- Boot, cloud-init, SSH, logging validation
- Evidence packet generation

## Evidence packet structure (future)

```
evidence/images/<name>/<version>/<UTC>/
  build-manifest.json
  acceptance.log
  sha256.txt
  manifest.sha256
```
