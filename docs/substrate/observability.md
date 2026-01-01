# Substrate Observability (Read-Only)

## Purpose

Provide deterministic, read-only runtime observation for Phase 11 substrates. This produces evidence packets that compare declared intent (contracts) to observed reality without mutating infrastructure.

## What this does

- Reads declared intent from `contracts/tenants/**/consumers/**/enabled.yml`.
- Performs best-effort reachability checks (TCP/HTTPS) only.
- Emits drift classification: `PASS`, `WARN`, or `FAIL`.
- Writes evidence under `evidence/tenants/<tenant>/<UTC>/substrate-observe/`.

## What this does NOT do

- No auto-remediation.
- No configuration changes.
- No restarts.
- No secret material handling.

## Drift semantics

- `PASS`: observed <= declared and semantics aligned.
- `WARN`: declared-only mode or soft-limit drift.
- `FAIL`: hard-limit drift or HA/SLO contract violation.

Drift `FAIL` does not auto-block CI; it is surfaced in evidence for operator review.

## Operator workflow

See the operator cookbook for canonical commands and evidence locations:

- `docs/operator/cookbook.md`
