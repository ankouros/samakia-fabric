# Consumer Quickstart

## 1. Validate contracts

```bash
make consumers.validate
make consumers.ha.check
make consumers.disaster.check
make consumers.gameday.mapping.check
```

## 2. Generate readiness evidence

```bash
make consumers.evidence
```

## 3. Generate bundles (operator handoff)

```bash
make consumers.bundle
make consumers.bundle.check
```

Evidence and bundles are written under gitignored paths:

- `evidence/consumers/...`
- `artifacts/consumer-bundles/...`

## Notes

These workflows are read-only. Any GameDay execute mode requires explicit guards.
