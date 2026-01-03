# AI Analysis Contract (Evidence-Bound)

Samakia Fabric uses **structured analysis requests** instead of free-form prompts.
Analysis is advisory only and never executes actions.

## Contract files

- `contracts/ai/analysis.schema.json`
- `contracts/ai/analysis.yml`

The schema enforces:
- explicit `analysis_type`
- explicit tenant scope
- evidence references and time window
- bounded `max_tokens`
- output format (`markdown` or `json`)

## Analysis types

- `drift_explain`: explain drift deltas from evidence
- `slo_explain`: explain SLO signals from evidence
- `incident_summary`: summarize incident evidence
- `plan_review`: summarize plan evidence (code-review model)
- `change_impact`: describe impact signals from evidence
- `compliance_summary`: summarize compliance evidence

## Evidence requirements

- Evidence references must live under `evidence/` and include the tenant id in the path.
- Evidence is fetched via the read-only Evidence MCP.
- Context is bounded (`AI_ANALYZE_MAX_*` limits) to avoid unbounded prompts.
- Redaction removes secret-like content and masks tenant identifiers for non-operators.

## Execution guards

- Dry-run is the default (`ai.analyze.plan`).
- Live execution requires `AI_ANALYZE_EXECUTE=1` and is blocked in CI.
- External providers are forbidden; Ollama-only routing applies.

## Evidence outputs

Each analysis writes a deterministic packet under:
`evidence/ai/analysis/<analysis_id>/<UTC>/`

Contents include:
- `analysis.yml.redacted`
- `inputs.json`
- `prompt.md`
- `model.json`
- `output.md`
- `manifest.sha256` (and optional signature)

## Model routing

Analysis types map to deterministic routing:
- ops analysis + summaries → `gpt-oss:20b`
- plan review → `starcoder2:15b`

Routing is defined in `contracts/ai/routing.yml`.
