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
