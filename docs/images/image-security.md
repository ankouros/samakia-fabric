# VM Image Security

VM golden images must adhere to the platform security model:

- SSH key-only access
- No passwords baked into the image
- Logging enabled (journald + syslog)
- Minimal package footprint
- Cloud-init enabled with deterministic datasource
- `/etc/samakia-image-version` stamped with build metadata

Operator commands live in `../operator/cookbook.md`.

Validate-only acceptance checks (offline) confirm:
- qcow2 format and size sanity
- cloud-init presence and enabled status
- SSH key-only posture in `sshd_config`
- build metadata and package manifest presence
- apt snapshot sources (if configured)

Runtime boot/SSH/logging validation is deferred to a later phase that performs
controlled VM boot checks.
