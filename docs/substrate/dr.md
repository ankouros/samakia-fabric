# DR Expectations (Design-Only)

Disaster recovery expectations are encoded in:
- `contracts/substrate/dr-testcases.yml`
- `dr.required_testcases` in each enabled contract

Validation ensures every enabled contract references known testcase IDs.

Operator commands: `docs/operator/cookbook.md` (substrate plan + DR dry-run).
