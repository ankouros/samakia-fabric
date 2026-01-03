# Incident Records (Phase 14 Part 3)

Incident records are bookkeeping artifacts.
They track classification, ownership, and resolution status without
triggering any automation.

## Alerts vs incidents

- Alerts surface signals and SLO states.
- Incidents are tracked records opened by operators after review.

## Open an incident

```bash
INCIDENT_ID=INC-123 TENANT=canary WORKLOAD=sample \
SIGNAL_TYPE=slo SEVERITY=WARN OWNER=operator \
EVIDENCE_REFS="evidence/alerts/canary/20260103T000000Z" \
make incidents.open
```

## Update an incident

```bash
INCIDENT_ID=INC-123 UPDATE_SUMMARY="Investigating latency" \
make incidents.update
```

## Close an incident

```bash
INCIDENT_ID=INC-123 RESOLUTION_SUMMARY="Issue resolved" \
make incidents.close
```

## Status values

- `open`
- `investigating`
- `mitigated`
- `closed`

## Evidence layout

```
evidence/incidents/<incident_id>/
  open.json
  updates/
  close.json
  manifest.sha256
  manifest.sha256.asc (prod if enabled)
```

## Safety notes

- Incident records never modify infrastructure.
- No remediation or automation is performed.
- Evidence references should point to alert or runtime evidence paths.
