# Runtime Operations (Design)

Runtime operations are evidence-driven and read-only by default.
No automation performs remediation or execution.

## Inputs (approved only)

- Drift evidence: `evidence/drift/**`
- Binding verification outputs: `evidence/bindings-verify/**`
- SLO declarations: `contracts/tenants/<tenant>/slo/*.yml`
- Observation policy: `contracts/runtime-observation/observation.yml`

## Classification workflow

1) Collect the latest evidence for the tenant/workload.
2) Classify using the runtime signal taxonomy:
   - Infrastructure Fault
   - Drift
   - SLO Violation
3) Record the decision and supporting evidence.

Classification order is strict and deterministic. Do not mix categories.

## Evidence layout (design only)

```
evidence/runtime/<tenant>/<workload>/<UTC>/
  signals.json
  classification.json
  slo-evaluation.json
  decision.md
  manifest.sha256
```

Evidence is redacted, deterministic, and secrets-free.

## Escalation guidance

- Infrastructure Fault: notify platform operations and substrate owners.
- Drift: notify contract owners and verify intended state.
- SLO Violation: notify the SLO owner (operator or tenant).

## What not to do

- Do not auto-remediate.
- Do not change infrastructure from CI.
- Do not write secrets into evidence or logs.
- Do not reclassify signals without new evidence.
