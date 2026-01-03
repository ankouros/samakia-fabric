# Tenant UX Contract for Self-Service (Phase 15 Part 4 — Design)

This document defines the tenant-facing expectations for controlled self-service.
It is **design-only**; no execution rights are granted.

## What tenants can do

- Submit proposals for operator review.
- Run validation and plan previews.
- View drift status, SLO status, and proposal outcomes.
- Receive evidence-backed decisions from operators.

## What tenants cannot do

- Apply changes or trigger execution.
- Access secrets or secret materialization outputs.
- Bypass policies or guardrails.
- Override operator decisions.

## What tenants should expect

- Explicit feedback on why a proposal is denied.
- Time-bounded reviews with clear status updates.
- Evidence references for approvals and rejections.
- Guidance on how to resubmit safely.

## Acceptable proposal examples

- Increase CPU/memory within documented capacity limits and risk budgets.
- Request a binding change that references an existing `secret_ref`.
- Propose exposure intent with a change window and rationale.

## Unacceptable proposal examples

- “Apply now” or “auto-approve” requests.
- Requests for secret values or token access.
- Attempts to bypass change windows or policy checks.
- Proposals that expand exposure without justification.

## Proposal lifecycle timeline (design)

- Submission: tenant submits proposal.
- Validation: tenant runs validation/plan preview.
- Review: operator evaluates scope, policy gates, and risk.
- Decision: approve, reject, or request changes.
- Execution: operator applies changes if approved.
- Evidence: tenant receives outcome and evidence link.

## Statement

Self-service remains proposal-only. Operator decisions are final and auditable.
