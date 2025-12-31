# Consumer Disaster Recovery

Every consumer contract must declare:
- disaster scenarios
- recovery expectations
- acceptance test cases (read-only by default)

Phase 6 does not execute recovery tests. It defines the contract and
maps test cases to Phase 3 GameDay patterns.

## Execute Mode (Opt-In)

SAFE GameDays can be executed only when:

- the environment is allowlisted (dev/staging)
- a maintenance window is provided
- an explicit reason is recorded
- evidence signing is enabled if required by policy

Execution policy is defined in:

`ops/consumers/disaster/execute-policy.yml`

Evidence is written under:

`evidence/consumers/gameday/<consumer>/<testcase>/<UTC>/`

Multi-party approval can be layered on top of execute mode by requiring
dual sign-off before `GAMEDAY_EXECUTE=1` is set (policy-driven, not automated).
