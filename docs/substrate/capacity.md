# Tenant Capacity & Quotas (Contract-Level)

Capacity is defined per tenant in `contracts/tenants/<tenant>/capacity.yml`.
The capacity guard evaluates **declared intent** from enabled contracts and
fails before apply/DR execute when limits are exceeded.

## What the guard enforces

- Per-consumer/provider logical limits (db/mq/cache/vector)
- Single vs cluster caps
- Default mode: `deny_on_exceed`
- Overrides must be explicit and reasoned

## What it does not do

- No runtime usage inspection (contract-only evaluation)
- No infrastructure mutation

## Evidence

Capacity checks write evidence under:

```
evidence/tenants/<tenant>/<UTC>/substrate-capacity/
```

Artifacts include:

- `computed-consumption.json`
- `limits.json`
- `decision.json`
- `capacity.yml.redacted`
- `manifest.sha256`

## Operator commands

See `docs/operator/cookbook.md` for copy/paste commands:

- `make tenants.capacity.validate TENANT=all`
- `make substrate.capacity.guard TENANT=all`
- `make substrate.capacity.evidence TENANT=all`
