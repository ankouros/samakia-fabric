# Drift Awareness (Tenant Signals)

Phase 12 Part 5 provides tenant-scoped drift signals without any remediation.

## What It Does

- Compares declared bindings and rendered manifests.
- Optionally ingests observed state evidence (if present).
- Classifies drift using the taxonomy in `docs/drift/taxonomy.md`.
- Emits tenant-visible summaries and operator evidence packets.

## What It Does NOT Do

- No remediation or apply.
- No automatic execution.
- No secrets in output.

## Evidence Locations

- `evidence/drift/<tenant>/<UTC>/` (operator evidence)
- `artifacts/tenant-status/<tenant>/` (tenant-facing summary)

## CLI Usage (Read-Only)

```bash
TENANT=all \
DRIFT_OFFLINE=1 \
DRIFT_NON_BLOCKING=1 \
DRIFT_FAIL_ON=none \
DRIFT_REQUIRE_SIGN=0 \
make drift.detect

TENANT=all make drift.summary
```

### Guard Variables

- `TENANT` (required): tenant id or `all`.
- `DRIFT_OFFLINE` (default `1`): use local evidence only.
- `DRIFT_NON_BLOCKING` (default `0`): exit 0 even if drift exceeds thresholds.
- `DRIFT_FAIL_ON` (`none|warn|critical`): when to exit non-zero.
- `DRIFT_REQUIRE_SIGN` (`auto|0|1`): enforce signing in prod if `auto`.

## Running Drift Detection

Use the operator cookbook for commands and guardrails:

- `docs/operator/cookbook.md`
