# GameDays — Failure Simulation (Phase 3 Part 2)

This runbook defines **safe, deterministic GameDay procedures** for validating
failover behavior without changing Phase 2.x contracts.

## Safety Model

GameDays are classified as:

- **SAFE**: read-only checks + controlled service transitions
- **DESTRUCTIVE**: node/CT stop or network disruption (opt-in only)

### Execution guards

SAFE actions require:

- `GAMEDAY_EXECUTE=1`

DESTRUCTIVE actions require **all** of:

- `GAMEDAY_EXECUTE=1`
- `GAMEDAY_DESTRUCTIVE=1`
- `I_UNDERSTAND=1`

No interactive prompts are used.

## Standard GameDay Run

1) **Precheck** (read-only)

```bash
make gameday.precheck
```

2) **Baseline evidence snapshot**

```bash
GAMEDAY_ID=gameday-$(date -u +%Y%m%dT%H%M%SZ) \
  make gameday.evidence
```

3) **VIP failover simulation (SAFE)**

```bash
# Dry-run only (default in acceptance)
make gameday.vip.failover.dry VIP_GROUP=minio

# Execute (requires GAMEDAY_EXECUTE=1)
GAMEDAY_EXECUTE=1 \
  bash ops/scripts/gameday/gameday-vip-failover.sh --vip-group minio --execute
```

4) **Service restart simulation (SAFE)**

```bash
# Dry-run only
make gameday.service.restart.dry SERVICE=keepalived TARGET=192.168.11.111

# Execute (requires GAMEDAY_EXECUTE=1)
GAMEDAY_EXECUTE=1 \
  bash ops/scripts/gameday/gameday-service-restart.sh \
    --service keepalived \
    --target 192.168.11.111 \
    --check-url https://192.168.11.122:3000/
```

5) **Postcheck + evidence diff**

```bash
GAMEDAY_ID=<same-as-baseline> make gameday.postcheck
```

## Evidence Artifacts

Evidence is written under:

- `artifacts/gameday/<GAMEDAY_ID>/<baseline|post>/<UTC>/report.md`
- `artifacts/gameday/<GAMEDAY_ID>/diff.txt` (if baseline + post exist)

## Dry-Run Acceptance Gate

Phase 3 Part 2 acceptance uses **dry-run only** actions:

```bash
make phase3.part2.accept
```

This runs:

- `gameday.precheck`
- baseline evidence snapshot
- dry-run VIP failover
- dry-run service restart
- postcheck evidence snapshot

## Notes

- All commands are **read-only** unless `GAMEDAY_EXECUTE=1` is set.
- No nftables changes are performed in SAFE mode.
- Destructive actions are not part of Phase 3 Part 2 acceptance.

## Consumer GameDay Execute Mode (Phase 6 Part 3)

Consumer GameDays can be executed **only** when the execution policy allows it.
The policy lives at:

`ops/consumers/disaster/execute-policy.yml`

### Guardrails (execute mode)

Execution requires all of:

- `GAMEDAY_EXECUTE=1`
- `I_UNDERSTAND_MUTATION=1`
- `ENV` is allowlisted (dev/staging only; **never prod**)
- `MAINT_WINDOW_START` and `MAINT_WINDOW_END` (UTC ISO)
- `GAMEDAY_REASON` (minimum length enforced)
- Signing enabled if required by policy (`EVIDENCE_SIGN=1` + `EVIDENCE_SIGN_KEY`)

Optional governance: require a second operator approval before setting
`GAMEDAY_EXECUTE=1` (documented policy; not automated).

### Example (SAFE execute)

```bash
ENV=samakia-staging \
GAMEDAY_EXECUTE=1 \
I_UNDERSTAND_MUTATION=1 \
MAINT_WINDOW_START=2025-01-01T00:00:00Z \
MAINT_WINDOW_END=2025-01-01T00:30:00Z \
GAMEDAY_REASON="VIP failover validation during maintenance" \
EVIDENCE_SIGN=1 \
EVIDENCE_SIGN_KEY=<fingerprint> \
bash ops/consumers/disaster/consumer-gameday.sh \
  --consumer contracts/consumers/kubernetes/ready.yml \
  --testcase gameday:vip-failover --execute
```

### Evidence

Execute-mode evidence is written to:

`evidence/consumers/gameday/<consumer>/<testcase>/<UTC>/`
