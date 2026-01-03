# Observability Operations

This document covers operator-facing workflows for shared observability.

## Policy checks (required)

Always validate policy before or after shared control-plane changes:

```bash
make shared.obs.policy ENV=samakia-shared
```

Policy violations are hard failures.

## Acceptance

Run shared observability acceptance (includes policy enforcement):

```bash
make shared.obs.accept ENV=samakia-shared
```

## Troubleshooting

If policy validation fails:

- Confirm at least two `obs-*` containers exist.
- Confirm each `obs-*` targets a distinct Proxmox host.
- Regenerate `terraform-output.json` by re-running `make tf.apply ENV=samakia-shared`.
