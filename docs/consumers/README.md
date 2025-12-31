# Platform Consumers

This section defines how higher-level platforms consume Samakia Fabric as a
**substrate**, not a managed platform.

Core model:
- Every consumer type has two variants:
  - `ready` (default): no service deployed; substrate and contract only.
  - `enabled` (opt-in): service exists externally; Fabric enforces the contract.
- Enabled variants must be declared in a manifest file (no auto-detection).
- HA-ready patterns are the default; overrides require explicit guardrails.

Start here:
- `catalog.md`
- `quickstart.md`
- `variants.md`
- `onboarding.md`
- `slo-failure-semantics.md`
- `disaster-recovery.md`

Contracts live under `contracts/consumers/`.
