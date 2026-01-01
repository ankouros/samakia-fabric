# DR Expectations and Safety

Disaster recovery expectations are encoded in:
- `contracts/substrate/dr-testcases.yml`
- `dr.required_testcases` in each enabled contract

Validation ensures every enabled contract references known testcase IDs.

## Dry-run only (Part 1)

Part 1 provides **dry-run only** planning and evidence. No backup or restore operations are executed.

Operator commands live in `docs/operator/cookbook.md`:
- `make substrate.dr.dryrun TENANT=all`

## Execute mode (Part 2, guarded)

Part 2 introduces **guarded DR execute** for backup + restore verification. Execute is never implicit and requires explicit guard variables and policy allowlists.

Guarded command (non-prod example):

```bash
TENANT_EXECUTE=1 I_UNDERSTAND_TENANT_MUTATION=1 EXECUTE_REASON="dr verification" \
DR_EXECUTE=1 ENV=samakia-dev TENANT=all \
make substrate.dr.execute
```

### Restore-to-temp strategy

Restore execution defaults to **integrity-only** checks. Optional restore-to-temp requires explicit guards:

```bash
RESTORE_TO_TEMP_NAMESPACE=1 I_UNDERSTAND_DESTRUCTIVE_RESTORE=1
```

Providers must never perform destructive restores by default.

## Evidence outputs

DR evidence packets are written under:

`evidence/tenants/<tenant>/<UTC>/substrate-dr-dryrun/`

DR execute evidence is written under:

`evidence/tenants/<tenant>/<UTC>/substrate-dr-execute/`

Artifacts are gitignored and redacted.
