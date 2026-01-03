# AI Conditional Autonomy Contracts (Design Only)

This directory defines the **design-only** contract for conditional, bounded
AI autonomy in Phase 17. It does not enable execution.

Files:
- `action.schema.json`: schema for explicitly allowlisted autonomy actions.

Contract rules:
- Actions must be explicit, deterministic, and reversible.
- Scope must be bounded to a tenant/workload/provider allowlist.
- Preconditions must be verified before any action.
- Rollback must be documented and executable by humans.
- Audit level is always `full`.

Non-goals:
- No autonomous execution paths.
- No cross-tenant impact.
- No dynamic command execution.
