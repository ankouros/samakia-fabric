# Alert Routing Contracts

This directory defines the default alert routing policy for Phase 11 Part 5 (drift alerting, evidence-only).

## Files

- `routing.yml`: default routing policy (JSON-compatible YAML).
- `alerting.schema.json`: schema for routing validation.

## Principles

- Evidence-first: local evidence is always written.
- No external delivery enabled by default.
- Explicit tenant allowlisting; no wildcards.
- Quiet hours and maintenance windows are respected.
- Production requires signed evidence and change-window context.

## Validation

Run:

```bash
make substrate.alert.validate
```

Validation enforces schema and routing safety constraints and fails on unsafe defaults.
