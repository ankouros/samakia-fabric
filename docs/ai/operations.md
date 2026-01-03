# AI Operations (Analysis-Only)

Samakia Fabric AI tooling is **advisory only**. It never executes changes.
The canonical operator entrypoint is `ops/ai/ops.sh`.

## Quickstart

```bash
bash ops/ai/ops.sh doctor
```

## Common workflows

### Explain drift

```bash
bash ops/ai/ops.sh analyze.plan FILE=examples/analysis/drift_explain.yml
```

### Summarize an SLO breach

```bash
bash ops/ai/ops.sh analyze.plan FILE=examples/analysis/slo_explain.yml
```

### Review an exposure plan

```bash
bash ops/ai/ops.sh analyze.plan FILE=examples/analysis/plan_review.yml
```

### Offline indexing (fixtures)

```bash
bash ops/ai/ops.sh index.offline TENANT=platform SOURCE=docs
```

## Guarded execution

Live analysis is operator-only and requires explicit flags:

```bash
RUNNER_MODE=operator \
AI_ANALYZE_EXECUTE=1 \
bash ops/ai/ops.sh analyze.run FILE=examples/analysis/drift_explain.yml
```

## Evidence index

```bash
bash ops/ai/evidence/rebuild-index.sh
bash ops/ai/evidence/validate-index.sh
```

To include local evidence runs:

```bash
RUNNER_MODE=operator AI_EVIDENCE_INDEX_MODE=local \
  bash ops/ai/evidence/rebuild-index.sh
```

Evidence index outputs:
- `evidence/ai/index.json`
- `evidence/ai/index.md`

## Troubleshooting

- **Blocked in CI**: set `RUNNER_MODE=operator` and re-run locally.
- **Missing guard flag**: set `AI_ANALYZE_EXECUTE=1` for guarded runs.
- **Invalid index**: run `bash ops/ai/evidence/rebuild-index.sh`.

## What AI will never do

- Execute commands or apply changes
- Remediate incidents or mutate infrastructure
- Bypass policy gates or MCP allowlists
- Use external AI providers

## Evidence locations

- Analysis: `evidence/ai/analysis/<analysis_id>/<UTC>/`
- Indexing: `evidence/ai/indexing/<tenant>/<UTC>/`
- MCP audit: `evidence/ai/mcp-audit/<UTC>/`
- Risk ledger: `evidence/ai/risk-ledger/`
