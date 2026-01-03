# AI Indexing (Analysis-Only)

Indexing ingests documents, contracts, runbooks, and evidence into Qdrant for
read-only AI analysis. It never performs remediation or execution.

## Offline vs live

Offline (CI-safe, default):
```bash
make ai.index.offline TENANT=platform SOURCE=docs
```

Live (operator-only, guarded):
```bash
AI_INDEX_EXECUTE=1 \
AI_INDEX_REASON="ticket-123: refresh docs" \
QDRANT_ENABLE=1 \
OLLAMA_ENABLE=1 \
make ai.index.live TENANT=platform SOURCE=docs
```

## Sources
- `docs`
- `contracts`
- `runbooks`
- `evidence`

## Redaction
Indexing refuses documents that match deny patterns (passwords, tokens, private
keys, kubeconfig, test secret marker). Denied files are logged in the evidence
packet and skipped.

## Evidence outputs
Indexing writes evidence under:
`evidence/ai/indexing/<tenant>/<UTC>/`

Artifacts include:
- `sources.json`
- `chunk-plan.json`
- `redaction.json`
- `embedding.json`
- `qdrant.json`
- `summary.md`
- `manifest.sha256`
