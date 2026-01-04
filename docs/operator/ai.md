# AI Operations (Analysis-Only)

AI in Samakia Fabric is advisory only. It **cannot** apply changes or execute actions.
Provider access is Ollama-only and routing is deterministic.
Context access uses read-only MCP services (Phase 16 Part 3).

## Quick checks

### AI configuration health (read-only)

```bash
bash ops/ai/ai.sh doctor
```

Expected result:
- Provider contract and routing policy validate
- Configuration summary prints without network calls

### Model routing lookup

```bash
bash ops/ai/ai.sh route ops.analysis
bash ops/ai/ai.sh route code.review
```

Expected result:
- Prints the model that would be used for the task

## Indexing (Phase 16 Part 2)

Offline (fixtures only):

```bash
make ai.index.offline TENANT=platform SOURCE=docs
```

Live (guarded, operator-only):

```bash
RUNNER_MODE=operator \
AI_INDEX_EXECUTE=1 \
AI_INDEX_REASON="ticket-123: refresh docs" \
QDRANT_ENABLE=1 \
OLLAMA_ENABLE=1 \
make ai.index.live TENANT=platform SOURCE=docs
```

Qdrant doctor (offline config vs live connectivity):

```bash
make ai.qdrant.doctor
RUNNER_MODE=operator AI_INDEX_EXECUTE=1 QDRANT_ENABLE=1 make ai.qdrant.doctor.live TENANT=platform
```

Evidence output:
`evidence/ai/indexing/<tenant>/<UTC>/`

## n8n ingestion workflows (read-only)

Validate workflow JSON and safety gates:

```bash
make ai.n8n.validate
```

Evidence output:
`evidence/ai/n8n/<UTC>/`

## MCP services (Phase 16 Part 3)

Doctor (config + allowlists, read-only):

```bash
make ai.mcp.doctor
```

Start servers locally (read-only):

```bash
make ai.mcp.repo.start
make ai.mcp.evidence.start
make ai.mcp.observability.start
make ai.mcp.runbooks.start
make ai.mcp.qdrant.start
```

Requests must include identity + tenant headers:

```bash
curl -sS -H "X-MCP-Identity: operator" -H "X-MCP-Tenant: platform" \\
  -H "Content-Type: application/json" \\
  -d '{"action":"list_files"}' http://127.0.0.1:8781/query
```

Live access is guarded (never in CI):
- Observability: `OBS_LIVE=1`
- Qdrant: `QDRANT_LIVE=1`

## AI analysis (Phase 16 Part 4)

Dry-run (CI-safe):

```bash
make ai.analyze.plan FILE=examples/analysis/drift_explain.yml
```

Guarded run (operator-only):

```bash
AI_ANALYZE_EXECUTE=1 make ai.analyze.run FILE=examples/analysis/drift_explain.yml
```

Evidence output:
`evidence/ai/analysis/<analysis_id>/<UTC>/`

## Design-only workflows (future Phase 16 parts)

- Run AI analysis on evidence packets (read-only, evidence-bound)
- Run AI review on plan output (read-only, evidence-bound)

## Non-negotiables
- Ollama-only provider
- Analysis-only mode
- No external AI providers
- No secrets in prompts or evidence
