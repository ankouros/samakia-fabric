# Operator Safety Model

## Read-only first

All operator workflows default to **read-only** execution. Mutating actions require explicit
guards, reasons, and evidence capture.

## Execute guards

Mutations must require explicit environment variables, for example:

- `IMAGE_REGISTER=1`
- `I_UNDERSTAND_TEMPLATE_MUTATION=1`
- `REGISTER_REASON="..."`

Exact guard names are documented per runbook and enforced by scripts.

## Evidence posture

Every operational action must produce a **secrets-safe evidence packet**:

- `report.md`
- `metadata.json`
- `manifest.sha256`
- optional signature (`manifest.sha256.asc`)

Evidence and artifacts are **gitignored** and must never be committed.

## Refusal rules

Operators (human or AI) must refuse to proceed when:

- TLS verification would be bypassed
- secrets would be printed or committed
- required guards are missing
- the action is outside the allowlisted environment
- acceptance or policy checks fail

## “03:00-safe” definition

A command is considered **03:00-safe** if it is:

- deterministic
- read-only by default
- guarded for execute mode
- produces evidence packets
- reversible or safely abortable
