# AI Contracts

This directory defines the AI provider and routing contracts for Samakia Fabric.

Files:
- `provider.schema.json` / `provider.yml`: Ollama-only provider contract (analysis-only).
- `routing.schema.json` / `routing.yml`: deterministic model routing policy.
- `qdrant.schema.json` / `qdrant.yml`: shared vector store contract.
- `indexing.schema.json` / `indexing.yml`: indexing + redaction policy.
- `analysis.schema.json` / `analysis.yml`: structured analysis requests and evidence bounds.

Validation:
- `bash ops/ai/validate-config.sh`
- `make policy.check`

Non-negotiables:
- Ollama-only provider (`http://192.168.11.30:11434`)
- No external AI providers
- Analysis-only mode (no execution)
