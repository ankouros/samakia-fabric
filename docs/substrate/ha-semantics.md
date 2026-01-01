# HA Semantics (Plan + DR Dry-Run)

All enabled substrate bindings must be HA-ready:
- `ha_ready: true`
- Variants: `single` (SPOF but DR required) or `cluster` (HA runtime)

Execution is not part of Part 1. Semantics are enforced by contract validation and
plan-only evidence.

Operator commands: `docs/operator/cookbook.md` (substrate plan + DR dry-run).
