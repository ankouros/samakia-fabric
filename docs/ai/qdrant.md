# Qdrant Contract (AI Indexing)

The shared Qdrant service backs AI analysis retrieval. The authoritative contract
is `contracts/ai/qdrant.yml`.

## Defaults
- Base URL: `http://192.168.11.122:6333`
- Auth: token optional (secret_ref only)
- TLS: not required by default (set to true if terminating TLS)
- Tenant isolation: collection-per-tenant
  - `kb_platform`
  - `kb_tenant_<tenant_id>`

## Non-negotiables
- No external Qdrant endpoints
- No secrets in Git (token via secret_ref only)
- Tenant isolation enforced in collection naming
