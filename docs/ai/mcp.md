# MCP Services (Read-Only Context)

Model Context Protocol (MCP) services expose **read-only** system context to AI
analysis. They never execute actions or mutate infrastructure.

## MCP catalog

- Repo MCP: repository files, diffs, and commit metadata (allowlisted paths only).
- Evidence MCP: evidence packets scoped to the requesting tenant.
- Observability MCP: predefined Prometheus/Loki queries (fixtures by default).
- Runbooks MCP: operator runbooks and procedures (allowlisted paths only).
- Qdrant MCP: read-only semantic search over indexed knowledge.

## Read-only guarantees

- No write or exec endpoints.
- Allowlisted paths and query names only.
- Tenant isolation enforced on every request.
- External network calls blocked in CI; fixtures are used by default.

## Allowlists (high level)

- Repo MCP: `ops/`, `docs/`, `contracts/`, `acceptance/`, plus `REVIEW.md`,
  `CHANGELOG.md`, `ROADMAP.md`.
- Evidence MCP: `evidence/` (tenant-scoped paths only).
- Observability MCP: named Prometheus/Loki queries defined in
  `ops/ai/mcp/observability/allowlist.yml`.
- Runbooks MCP: `ops/runbooks/` and `docs/operator/`.
- Qdrant MCP: base URL defined in `ops/ai/mcp/qdrant/allowlist.yml`.

## Tenant isolation + identity

Every request must include:

- `X-MCP-Identity`: `operator` or `tenant`
- `X-MCP-Tenant`: tenant id (operators are restricted to `platform`)

Requests without identity/tenant are rejected.

## Audit logging

Every MCP request writes an audit record under:

`evidence/ai/mcp-audit/<UTC>/`

Files:
- `request.json`
- `decision.json`
- `response.meta.json`
- `manifest.sha256`

No secrets are written; payloads are redacted or denied.

## CI behavior

- `MCP_TEST_MODE=1` (or `CI=1`) forces fixtures for MCPs that require network
  access (observability and Qdrant).
- Live access is guarded:
  - Observability: `OBS_LIVE=1`
  - Qdrant: `QDRANT_LIVE=1`

## Operator entrypoints

- `make ai.mcp.doctor`
- `make ai.mcp.repo.start`
- `make ai.mcp.evidence.start`
- `make ai.mcp.observability.start`
- `make ai.mcp.runbooks.start`
- `make ai.mcp.qdrant.start`
