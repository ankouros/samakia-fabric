# Phase 13 Entry Checklist

Timestamp (UTC): 2026-01-02T17:57:27Z

## Hard gates
- Milestone Phase 1-12 regression marker exists and is PASS-locked
  - Command: test -f acceptance/MILESTONE_PHASE1_12_ACCEPTED.md
  - Result: PASS
- REQUIRED-FIXES.md has no OPEN items
  - Command: rg -n "OPEN" REQUIRED-FIXES.md
  - Result: PASS
- Phase 11 hardening accepted
  - Command: test -f acceptance/PHASE11_HARDENING_ACCEPTED.md
  - Result: PASS
- Phase 12 closure accepted (readiness packet exists)
  - Command: test -f acceptance/PHASE12_ACCEPTED.md
  - Result: PASS
- CI policy gates PASS
  - Command: make policy.check
  - Result: PASS
- Exposure policy contract exists and validates
  - Command: python3 - <<'PY' (schema validation)
  - Result: PASS

## Operational prerequisites
- Signing key configured for prod (documented)
  - Command: rg -n "signing" docs/exposure/change-window-and-signing.md
  - Result: PASS
- Change window process defined (documented)
  - Command: rg -n "Change Window" docs/exposure/change-window-and-signing.md
  - Result: PASS
- Canary tenant selected in policy (default)
  - Command: rg -n "canary" contracts/exposure/exposure-policy.yml
  - Result: PASS
- Rollback runbook exists
  - Command: test -f docs/exposure/rollback.md
  - Result: PASS
