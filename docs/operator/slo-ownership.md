# SLO Ownership

SLO ownership is explicit and contractual. Every SLO declaration must specify
an owner and scope.

## Owners

- Operator: platform-managed workloads, shared services, and substrate SLOs.
- Tenant: tenant-owned workloads and application-level objectives.

## Owner responsibilities

Operators:
- Define and review SLO objectives for platform workloads.
- Classify incidents using evidence.
- Decide if investigation or rollback is required.

Tenants:
- Define and review workload SLOs.
- Participate in incident classification and follow-up actions.

## Contract requirements

SLO declarations must include:
- scope (tenant, workload, provider)
- objectives (availability, latency, error rate)
- measurement window
- error budget
- severity mapping (warn, critical)
- owner (operator or tenant)

Ownership determines who is notified and who approves follow-up actions.
