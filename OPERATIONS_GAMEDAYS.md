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
