# AI Operations Guide (Operators)

AI in Samakia Fabric is **analysis-only**. It cannot execute actions.
Use the unified entrypoint: `ops/ai/ops.sh`.

## One-page usage guide

### 1) Validate configuration

```bash
bash ops/ai/ops.sh doctor
```

### 2) Offline indexing (fixtures)

```bash
bash ops/ai/ops.sh index.preview TENANT=platform SOURCE=docs
bash ops/ai/ops.sh index.offline TENANT=platform SOURCE=docs
```

### 3) Draft an analysis plan

```bash
bash ops/ai/ops.sh analyze.plan FILE=examples/analysis/drift_explain.yml
```

### 4) Guarded analysis run (operator-only)

```bash
RUNNER_MODE=operator \
AI_ANALYZE_EXECUTE=1 \
bash ops/ai/ops.sh analyze.run FILE=examples/analysis/drift_explain.yml
```

## Common workflows

- Explain drift: `examples/analysis/drift_explain.yml`
- Summarize SLO breach: `examples/analysis/slo_explain.yml`
- Review exposure plan: `examples/analysis/plan_review.yml`

## Troubleshooting

- **Blocked in CI**: ensure `RUNNER_MODE=operator`.
- **Missing guard**: set `AI_ANALYZE_EXECUTE=1`.
- **Index drift**: run `bash ops/ai/evidence/rebuild-index.sh`.

## What AI will NEVER do

- Execute commands or apply infrastructure changes
- Remediate incidents or mutate state
- Use external AI providers
- Override policy gates or MCP allowlists

## Authoritative references

- AI invariants: `contracts/ai/INVARIANTS.md`
- Platform manifest: `docs/platform/PLATFORM_MANIFEST.md`

## Evidence locations

- `evidence/ai/analysis/<analysis_id>/<UTC>/`
- `evidence/ai/indexing/<tenant>/<UTC>/`
- `evidence/ai/mcp-audit/<UTC>/`
- `evidence/ai/index.json` and `evidence/ai/index.md`
- `evidence/ai/risk-ledger/`

To include local evidence in the index:

```bash
RUNNER_MODE=operator AI_EVIDENCE_INDEX_MODE=local \
  bash ops/ai/evidence/rebuild-index.sh
```
