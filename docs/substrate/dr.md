# DR Expectations and Safety

Disaster recovery expectations are encoded in:
- `contracts/substrate/dr-testcases.yml`
- `dr.required_testcases` in each enabled contract

Validation ensures every enabled contract references known testcase IDs.

## Dry-run only (Part 1)

Part 1 provides **dry-run only** planning and evidence. No backup or restore operations are executed.

Operator commands live in `docs/operator/cookbook.md`:
- `make substrate.dr.dryrun TENANT=all`

## Evidence outputs

DR evidence packets are written under:

`evidence/tenants/<tenant>/<UTC>/substrate-dr-dryrun/`

Artifacts are gitignored and redacted.
