# SLO Contracts

This directory defines the SLO contract schema used to declare runtime objectives
per tenant and workload.

## Files

- `slo.schema.json`: JSON schema for Workload SLO declarations.

## Declaration location

SLO declarations live under:

- `contracts/tenants/<tenant>/slo/<workload>.yml`

## Principles

- SLOs are declared, not enforced automatically.
- Owners are explicit (operator or tenant).
- Objectives are evaluated deterministically against declared windows.
- Error budgets are conceptual until runtime tooling evaluates them.

## Validation

Phase 14 acceptance validates SLO declarations against `slo.schema.json`.
