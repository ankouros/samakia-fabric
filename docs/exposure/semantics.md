# Exposure Semantics

Exposure is the **governed act of generating connection artifacts** for an
approved tenant workload. It is a **choreography** (plan -> approve -> apply ->
verify -> rollback), not a toggle and not an autonomous action.

## What Exposure Is

- Produces consumer-ready connection bundles/manifests based on Phase 12 bindings.
- Places artifacts in `artifacts/exposure/<env>/<tenant>/<workload>/`.
- Emits evidence packets for every step under `evidence/exposure-*/...`.

## What Exposure Is Not

- Not substrate provisioning (still Phase 11).
- Not secret materialization (still Phase 10/Phase 12 Part 2).
- Not CI-driven execution; CI is read-only.

## Invariants

- TLS is mandatory; plaintext endpoints are forbidden.
- Exposure policy must allow env/tenant/workload/provider/variant.
- Prod requires approval, signing, and a change window.

## Plan vs Apply

- **Plan**: read-only evaluation of policy + rendered bindings. Produces a
  deterministic plan and evidence without writing any exposure artifacts.
- **Apply**: guarded execution that writes exposure artifacts only after
  approval, signatures, and change window checks pass.

## Verify and Rollback

- **Verify**: read-only bindings verification + drift snapshot (live mode is guarded).
- **Rollback**: removes exposure artifacts only, then verifies baseline drift.

See `docs/operator/exposure.md` for the operator workflow.
