# Runtime Signal Taxonomy

Samakia Fabric classifies runtime signals into exactly three classes.
These classes are mutually exclusive and must not be mixed.

## 1) Drift

Definition:
- Declared state does not match observed state.

Examples:
- Binding contract differs from live substrate evidence.
- Capacity guard evidence indicates overage.
- Exposure artifacts are missing or unexpected.

Sources:
- Phase 11 drift evidence packets.
- Phase 12 bindings verification outputs.

## 2) SLO Violation

Definition:
- The workload meets declared configuration, but fails declared objectives.

Examples:
- Availability below target.
- Latency p95/p99 above limits.
- Error rate above threshold or error budget exhausted.

Sources:
- SLO contracts under `contracts/tenants/<tenant>/slo/`.
- Approved metrics listed in `contracts/runtime-observation/observation.yml`.

## 3) Infrastructure Fault

Definition:
- Substrate or network failure prevents normal operation.

Examples:
- Host unreachable.
- Network partition evidence present.
- TLS handshake failures.

Sources:
- Phase 11 observe outputs.
- Phase 12 verification evidence.

## Non-overlap rule

A signal must be classified into one class only:

- Drift is not an SLO violation.
- SLO violation is not an infrastructure fault.
- Infrastructure fault is not drift.

If multiple inputs exist, the classification order is enforced by tooling and
recorded in evidence.

## Reference implementation (Phase 14 Part 1)

Runtime evaluation is implemented as a read-only engine:

- `make runtime.evaluate TENANT=<id|all>`
- `make runtime.status TENANT=<id|all>`

Classification order is deterministic:

1) Infrastructure Fault
2) Drift
3) SLO Violation
4) OK
