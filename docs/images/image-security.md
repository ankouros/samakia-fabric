# VM Image Security

VM golden images must adhere to the platform security model:

- SSH key-only access
- No passwords baked into the image
- Logging enabled (journald + syslog)
- Minimal package footprint
- Cloud-init enabled with deterministic datasource

Acceptance tests validate:
- boot success
- cloud-init completion
- SSH reachability (key-only)
- logging availability
- package pinning where applicable
