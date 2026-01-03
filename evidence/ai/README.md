# AI Evidence Index

This directory holds the canonical index of AI evidence runs.

- `index.json`: machine-readable index of AI runs (analysis, indexing, MCP audit, plan review)
- `index.md`: human-readable index with the same content
- `risk-ledger/`: descriptive ledger entries for AI usage outcomes

## Rebuild

```bash
bash ops/ai/evidence/rebuild-index.sh
```

By default, the index runs in **CI-safe mode** (no local evidence). To include
local evidence runs, set:

```bash
RUNNER_MODE=operator AI_EVIDENCE_INDEX_MODE=local \
  bash ops/ai/evidence/rebuild-index.sh
```

## Validate

```bash
bash ops/ai/evidence/validate-index.sh
```

## Notes

- The index is metadata-only; evidence content remains under `evidence/ai/**` (gitignored).
- Provide `AI_OPERATOR=<name>` to tag the index with the operator identity.
