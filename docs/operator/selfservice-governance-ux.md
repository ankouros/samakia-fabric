# Operator UX for Self-Service Governance (Phase 15 Part 4 — Design)

This document explains how operators review self-service proposals without
losing context or control. It is design-only.

## Efficient review workflow

- Confirm identity, tenant scope, and environment.
- Read the proposal intent and justification.
- Review policy checks, risk budget status, and drift context.
- Ensure change windows and signatures are included for prod.

## Communicating “no” constructively

- Provide a concise reason tied to a guardrail.
- Offer a safer alternative or smaller scope.
- Reference evidence links to avoid ambiguity.

## Scoping approvals safely

- Limit scope to a single workload or binding where possible.
- Time-bound approvals with explicit review windows.
- Require follow-up evidence for higher-risk changes.

## Revoking autonomy or approvals

- Revoke immediately on incidents or policy violations.
- Record the revocation reason and evidence link.
- Require an explicit operator review to reinstate.

## Escalating decisions

- Escalate when risk budget is exhausted or scope is large.
- Include proposal context, risk summary, and recommended action.

## Example review checklist

- [ ] Identity and tenant scope verified
- [ ] Proposal intent documented and justified
- [ ] Policy gates passed (or clearly failed with rationale)
- [ ] Risk budget within limits
- [ ] Change window and signatures (prod)
- [ ] Evidence links attached
- [ ] Decision recorded and communicated
