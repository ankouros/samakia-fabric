# n8n Ingestion Workflows (Read-Only)

These workflows are templates for **read-only** ingestion orchestration. They are
intended to:
- read from repo/evidence directories
- emit deterministic indexing requests into a local queue directory
- avoid any apply/remediation paths

## Queue directory

Workflows write request files under:
`/var/lib/samakia/ai-index-queue/`

The queue directory is consumed by a guarded operator run of the indexer.
No workflow should execute commands directly.

## Credentials

Do not store credentials in workflow JSON. If credentials are required, reference
`secret_ref` values in n8n and resolve them outside the repo.

## Validation

Validate workflow structure and safety (CI-safe):

```bash
make ai.n8n.validate
```

Validation writes evidence under:
`evidence/ai/n8n/<UTC>/`

## Guardrails

- No external endpoints
- No write/exec/SSH nodes
- Deterministic, disabled-by-default workflows (active=false)
