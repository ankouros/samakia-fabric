# Consumer Variants

## ready (default)

- No service deployed
- Fabric provides HA-ready substrate contracts
- Intended for consumer-managed installations

## enabled (opt-in)

- Service exists and is declared explicitly by manifest
- Fabric enforces compliance against the contract
- No runtime auto-detection

## Evidence expectations

- Drift packets (substrate)
- Readiness packets (consumer)
- Compliance packets (if applicable)
