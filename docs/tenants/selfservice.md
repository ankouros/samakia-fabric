# Tenant Self-Service Proposals (Phase 15 Part 1)

Phase 15 introduces **controlled self-service**. Tenants may submit proposals and
run read-only validation/plan previews, but **cannot apply changes**. Operators
retain full control over approvals and execution.

## What tenants can do

- Submit proposal YAML describing desired changes.
- Run read-only validation, diff, impact, and plan previews.
- See policy requirements and required approvals.

## What tenants cannot do

- Apply changes (no apply paths are exposed).
- Access secrets or credentials.
- Bypass policy gates or operator approval.
- Execute any runtime mutations.

## Proposal contract

- Schema: `contracts/selfservice/proposal.schema.json`
- Example: `examples/selfservice/example.yml`

Required fields:
- `proposal_id`, `tenant_id`, `requested_by`, `requested_at`
- `scope` (bindings, capacity, exposure_request)
- `desired_changes` (declarative path/value changes)
- `justification`, `target_env`, `expires_at`

Rules:
- Capacity requests are **increase-only**.
- Exposure requests are **intent-only** (request, not apply).
- Secrets/credentials are forbidden.
- Proposals expire automatically if `expires_at` is in the past.

## Lifecycle (read-only)

1. Prepare proposal YAML.
2. Submit proposal (immutable inbox entry):
   ```bash
   make selfservice.submit FILE=<proposal.yml>
   ```
3. Validate proposal:
   ```bash
   make selfservice.validate PROPOSAL_ID=<id>
   ```
4. Generate a read-only plan preview:
   ```bash
   make selfservice.plan PROPOSAL_ID=<id>
   ```
5. Operator reviews evidence:
   ```bash
   make selfservice.review PROPOSAL_ID=<id>
   ```

## Evidence

Evidence packets are written under:
`evidence/selfservice/<tenant>/<proposal_id>/` (gitignored)

Evidence includes:
- `proposal.yml`
- `validation.json`
- `diff.md`
- `impact.json`
- `plan.json`
- `summary.md`
- `manifest.sha256`

See also:
- `docs/operator/selfservice-review.md`
- `docs/operator/cookbook.md`
