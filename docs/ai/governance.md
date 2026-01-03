# AI Governance Model

AI in Samakia Fabric is **analysis-only** and permanently advisory.
It exists to help operators understand evidence, not to act.

## Scope of AI usage

- Analysis, summarization, and explanation only
- Evidence-bound prompts and outputs
- Read-only MCP access

## Explicit prohibitions

- No execution of actions
- No remediation or apply paths
- No decision authority
- No external AI providers
- No CI live AI calls

## Roles

- **Operator**: runs AI analysis tools and reviews outputs
- **Tenant**: may view approved outputs only (read-only)
- **Platform owner**: controls AI policy and scope changes

## Review cadence

- Quarterly review of AI usage and evidence quality
- Review includes: policy adherence, regression tests, and incident impact

## Change control

- Any new AI capability requires a new phase and acceptance marker
- Changes must update contracts, policy gates, docs, and tests

## Decommissioning

If AI must be disabled:

1) Set `AI_ANALYZE_DISABLE=1` in the operator environment
2) Remove AI targets from operator workflows
3) Record the decision and evidence in the risk ledger

**AI is advisory. Responsibility never transfers from humans.**
