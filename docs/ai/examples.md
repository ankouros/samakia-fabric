# AI Analysis Examples

All analysis requests use the structured contract. Use the examples under
`examples/analysis/` as a starting point.

## Drift explain (dry-run)

```bash
make ai.analyze.plan FILE=examples/analysis/drift_explain.yml
```

## Incident summary (tenant read-only)

```bash
make ai.analyze.plan FILE=examples/analysis/incident_summary.yml
```

## Plan review (operator)

```bash
make ai.analyze.plan FILE=examples/analysis/plan_review.yml
```

## Live run (guarded)

```bash
AI_ANALYZE_EXECUTE=1 make ai.analyze.run FILE=examples/analysis/drift_explain.yml
```

Live execution is blocked in CI and requires the evidence MCP to be available.
Evidence packets are written under `evidence/ai/analysis/<analysis_id>/<UTC>/`.
