# AI Runbook Format (Strict)

All AI-readable runbooks in `ops/runbooks/ai/` MUST include the following sections, in order:

1) `## Preconditions`
2) `## Commands`
3) `## Decision Points`
4) `## Refusal Conditions`
5) `## Evidence Artifacts`
6) `## Exit Criteria`

Additional sections are allowed **after** these headings.

Rules:
- Commands are read-only by default.
- Any execute path must be explicitly guarded.
- Runbooks must never print secrets.
- Use deterministic, copy/paste-safe commands.
