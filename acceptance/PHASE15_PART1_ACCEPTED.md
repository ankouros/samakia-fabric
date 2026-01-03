# Phase 15 Part 1 Acceptance

Timestamp (UTC): 2026-01-03T02:11:57Z
Commit: afdcdb016be60904cc6ff9630250a0bfb62555c1

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make selfservice.submit FILE=examples/selfservice/example.yml
- make selfservice.validate PROPOSAL_ID=example
- make selfservice.plan PROPOSAL_ID=example
- make selfservice.review PROPOSAL_ID=example
- make phase15.part1.entry.check
- PROPOSAL_APPLY=1 make selfservice.plan PROPOSAL_ID=example (expected fail)

Result: PASS

Evidence:
- /home/aggelos/samakia-fabric/evidence/selfservice/canary/example

Statement:
Phase 15 Part 1 enables proposal-only self-service; no tenant can apply changes.

Self-hash (sha256 of content above): fada74c118b30b4a71674d2d3afe7936e39858bfc64636085cdeb7acdcf83445
