# Substrate DR Taxonomy

This directory defines the **canonical DR testcase IDs** for tenant-scoped substrate executors.

Use these IDs in:
- `contracts/tenants/**/consumers/**/enabled.yml` under `dr.required_testcases`
- Phase 11 validation scripts under `ops/substrate/`

Rules:
- IDs are stable, lowercase, and underscore-separated.
- The taxonomy is **design-only** and contains no execution logic.
- Adding or changing IDs requires updating ADR-0029 and validation tooling.
