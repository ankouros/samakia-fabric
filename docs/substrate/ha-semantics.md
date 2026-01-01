# HA Semantics (Design-Only)

All enabled substrate bindings must be HA-ready:
- `ha_ready: true`
- Variants: `single` (SPOF but DR required) or `cluster` (HA runtime)

No execution occurs in this phase. These semantics are enforced by contract validation only.

Operator commands: `docs/operator/cookbook.md` (substrate plan + DR dry-run).
