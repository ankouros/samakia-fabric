# Alert Delivery (Phase 14 Part 3)

Alert delivery is controlled, evidence-backed, and operator-managed.
No remediation or automation is performed.

## Inputs (read-only)

- Runtime evaluation evidence: `evidence/runtime-eval/**`
- SLO evaluation evidence: `evidence/slo/**`
- SLO alert readiness rules: `artifacts/slo-alerts/**`
- Routing policy: `contracts/alerting/routing.yml`

No direct metric scraping occurs in this phase.

## Validate alert routing + formatting

```bash
make alerts.validate
```

This validates routing policy and alert formatting output.

## Controlled delivery (guarded)

Alert delivery is disabled by default. To stage an alert delivery run:

```bash
ALERTS_ENABLE=1 ALERT_SINK=slack \
  make alerts.deliver TENANT=<id|all>
```

Requirements:
- `ALERTS_ENABLE=1` must be set.
- `ALERT_SINK` must be `slack`, `webhook`, or `email`.
- CI always suppresses delivery.
- Routing policy must allow the tenant/environment/provider.
- Routing policy delivery + sink flags must be enabled.

## Quiet hours and change windows

- WARN alerts are suppressed during quiet hours.
- CRITICAL alerts are always surfaced (evidence-backed), even during quiet hours.
- Production delivery respects change window context (`CHANGE_WINDOW_START` and
  `CHANGE_WINDOW_END` when required by routing policy).

## Evidence layout

```
evidence/alerts/<tenant>/<UTC>/
  signals.json
  slo.json
  routing.json
  decision.json
  delivery.json
  manifest.sha256
  manifest.sha256.asc (prod if enabled)
```

Evidence is deterministic, redacted, and secrets-free.

## Safety notes

- No alert delivery happens without explicit enablement.
- No secrets are embedded in alerts or evidence.
- No remediation or automation is triggered.
