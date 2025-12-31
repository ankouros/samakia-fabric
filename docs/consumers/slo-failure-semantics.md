# SLO and Failure Semantics

Guided flows: `catalog.md` and `quickstart.md`.

Consumer contracts define failure semantics by tier:
- tier0: control-plane critical
- tier1: stateful core
- tier2: non-critical

Default semantics:
- tier0/tier1 are HA-ready with anti-affinity across failure domains.
- overrides require explicit guardrails and reasons.

Acceptance tests in Phase 6 design are read-only and evidence-driven.
