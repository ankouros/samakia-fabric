# AI Operations Policy — Samakia Fabric

This policy defines **how AI agents may participate** in operations inside Samakia Fabric.
It is binding for humans, CI, and automation.

## Scope

AI assistance is permitted **only** within explicit, auditable boundaries.
Default posture is **read-only**.

## Allowed Tasks (Read-Only Default)

- Read-only analysis of plans, logs, and evidence packets
- Evidence packet generation (manifest + metadata)
- Documentation updates that reflect implemented behavior
- Suggestions and summaries with no changes applied
- Execution of explicitly allowlisted **03:00-safe** read-only scripts

## Disallowed Tasks (Always Refuse)

- Destructive actions (delete, destroy, stop services, reboot)
- Secret exfiltration or printing sensitive values
- Bypassing policy gates, guards, or acceptance workflows
- Modifying production infrastructure without explicit human approval
- Running arbitrary shell commands outside the allowlist

## Refusal Rules (Stop Immediately)

AI agents **must stop** if any of the following are true:

- Required acceptance markers are missing
- REQUIRED-FIXES.md has OPEN items
- Any request implies bypassing guardrails
- Secrets would be exposed in output or logs
- Execution requires interactive prompts in CI mode

## Escalation Path

When execution is requested:

1. Require explicit guard variables (see remediation workflow).
2. Require a human-provided reason and maintenance window.
3. Require evidence packet output and, if configured, a signature.
4. If any guard is missing, refuse and request operator action.

## Evidence Requirements

Any mutation (if ever allowed) must produce:

- `plan.md` describing intent
- `execution.log` (redacted)
- `postchecks.md` with verification
- `manifest.sha256` and optional signature

Evidence packets are **never committed** and must be stored under `evidence/`.

## 03:00-Safe Definition

A script/target is **03:00-safe** if it is:

- Read-only by default
- Deterministic and non-interactive
- Secrets-safe (no printing of tokens/keys)
- Allowlisted in `ops/scripts/safe-index.yml`
- Executed via `ops/scripts/safe-run.sh`

## Controlled Remediation (Opt-In)

Remediation is **opt-in** and must be guarded:

- `AI_REMEDIATE=1`
- `AI_REMEDIATE_REASON="<text>"`
- `ENV=<allowlisted env>` (never prod by default)
- `MAINT_WINDOW_START/END` (UTC)
- `I_UNDERSTAND_MUTATION=1`

Without these guards, remediation **must refuse**.
