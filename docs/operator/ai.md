# AI Operations (Analysis-Only)

AI in Samakia Fabric is advisory only. It **cannot** apply changes or execute actions.
Provider access is Ollama-only and routing is deterministic.
Future context access uses read-only MCP services (Phase 16 Part 3).

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

## Design-only workflows (tooling arrives in later Phase 16 parts)

- Run AI analysis on evidence packets (read-only, evidence-bound)
- Run AI review on plan output (read-only, evidence-bound)

## Non-negotiables
- Ollama-only provider
- Analysis-only mode
- No external AI providers
- No secrets in prompts or evidence
