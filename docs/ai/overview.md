# AI Overview (Analysis-Only)

Samakia Fabric supports AI-assisted analysis for **understanding** the system.
It never grants AI any execution or remediation capability.

## Scope
- Analysis, summarization, and explanation only
- Read-only inputs (contracts, evidence, runbooks, docs)
- Deterministic routing and provider configuration
- MCP access is read-only and available in Phase 16 Part 3
- Indexing is offline-first with guarded live runs (Phase 16 Part 2)
- Analysis UX and evidence-bound reports (Phase 16 Part 4)

## Non-goals
- No automation or apply paths
- No external AI providers
- No secrets in prompts or outputs

## References
- AI invariants (authoritative): `../../contracts/ai/INVARIANTS.md`
- Provider: `provider.md`
- Routing: `routing.md`
- Indexing: `indexing.md`
- MCP services: `mcp.md`
- Analysis contract: `analysis.md`
- Analysis examples: `examples.md`
- Governance: `governance.md`
- Stop rules: `stop-rules.md`
- Risk ledger: `risk-ledger.md`
- Operations: `operations.md`
- Operator usage: `../operator/ai.md`
