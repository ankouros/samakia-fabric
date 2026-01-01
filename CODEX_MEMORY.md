# Codex Memory

## Phase 11 Part 4 Summary
- Added read-only substrate observability + drift compare tooling under `ops/substrate/observe/` and provider wrappers in `ops/substrate/*/`.
- Added Phase 11 Part 4 entry/accept scripts and acceptance markers under `acceptance/`.
- Wired Makefile targets for observe/compare/evidence and Phase 11 Part 4 entry/accept.
- Updated docs/runbooks (operator cookbook, substrate observability doc, OPERATIONS/REVIEW/ROADMAP/CHANGELOG).
- Added PR validation gates for `substrate.observe` and `substrate.observe.compare`.

## Tests Run
- `pre-commit run --all-files`
- `bash fabric-ci/scripts/lint.sh`
- `bash fabric-ci/scripts/validate.sh`
- `make policy.check`
- `make tenants.capacity.validate TENANT=all`
- `make substrate.observe TENANT=all`
- `make substrate.observe.compare TENANT=all`
- `make phase11.part4.entry.check`
- `make phase11.part4.accept`

## Phase 11 Part 5 Summary
- Added drift alert routing defaults under `contracts/alerting/` with strict env-aligned policy.
- Added alert routing validation under `ops/substrate/alert/` and Phase 11 Part 5 entry/accept scripts.
- Wired Makefile targets and PR validation to enforce `substrate.alert.validate`.
- Updated operator docs and governance docs to reference alert routing defaults and acceptance.

## Tests Run (Part 5)
- `make policy.check`
- `make substrate.alert.validate`
- `make phase11.part5.entry.check`
- `make phase11.part5.routing.accept`

## Phase 11 Hardening Gate (JSON Checklist) Summary
- Added JSON-based hardening checklist source of truth under `hardening/` with schema, validation, and render tooling.
- Updated hardening entry/accept scripts to use the JSON checklist, generate operator-facing Markdown, and emit a JSON acceptance marker.
- Added Make targets for checklist validate/render/summary and wired PR validation to run the summary gate.
- Updated governance and operator docs to reference the generated hardening docs and acceptance marker.

## Tests Run (Hardening Gate)
- `pre-commit run --all-files`
- `bash fabric-ci/scripts/lint.sh`
- `bash fabric-ci/scripts/validate.sh`
- `make hardening.checklist.validate`
- `make hardening.checklist.render`
- `make hardening.checklist.summary`
- `make phase11.hardening.entry.check`
- `make phase11.hardening.accept`
