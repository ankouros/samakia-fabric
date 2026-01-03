# AI Analysis Runbook (Phase 16 Part 4)

AI analysis is **read-only** and evidence-bound. It never executes or remediates.

## Prerequisites

- Evidence MCP available (local read-only service).
- Analysis request file (see `examples/analysis/`).

Start the evidence MCP locally if needed:

```bash
make ai.mcp.evidence.start
```

## Dry-run (CI-safe)

```bash
make ai.analyze.plan FILE=examples/analysis/drift_explain.yml
```

This produces an evidence packet under:
`evidence/ai/analysis/<analysis_id>/<UTC>/`

## Live run (guarded, operator-only)

```bash
AI_ANALYZE_EXECUTE=1 make ai.analyze.run FILE=examples/analysis/drift_explain.yml
```

Guards:
- `AI_ANALYZE_EXECUTE=1` is required
- live execution is blocked in CI

## Evidence signing (optional)

```bash
EVIDENCE_SIGN=1 EVIDENCE_GPG_KEY=<FPR> AI_ANALYZE_EXECUTE=1 \
  make ai.analyze.run FILE=examples/analysis/drift_explain.yml
```

## Redaction behavior

- Secret-like content is removed from prompts and outputs.
- Tenant identifiers are masked for non-operator requests.

## Failure modes

- Missing evidence MCP or tenant isolation mismatch
- Evidence refs outside `evidence/` or missing tenant path
- Redaction detects secret patterns
