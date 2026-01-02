# Drift Taxonomy

This taxonomy is the single source of truth for tenant drift classification.

## Classes

- **none**: No drift detected.
- **expected**: Drift is declared (override/change window) and acknowledged.
- **configuration**: Declared bindings or rendered manifests do not match.
- **capacity**: Declared intent exceeds capacity/quotas.
- **security**: Secret-like material or policy violations detected.
- **availability**: Observed endpoints are down or failing checks.
- **unknown**: Drift cannot be determined due to missing observations.

## Severity Mapping

- **info**: no drift or expected drift.
- **warn**: configuration or capacity drift without hard denial.
- **critical**: security or availability drift, or capacity drift in deny mode.

## Ownership

- Tenant-visible: `configuration`, `capacity`, `availability`, `unknown`.
- Operator-only: `security` and any drift that requires remediation.

## Non-Remediation Rule

Drift classification is read-only. It must never trigger remediation.
