# Runner Modes (CI vs Operator)

Samakia Fabric enforces a runner contract to keep automation deterministic
and safe.

## RUNNER_MODE

- `RUNNER_MODE=ci` (default): non-interactive, read-only by default
- `RUNNER_MODE=operator`: interactive prompts allowed when explicitly required

## CI mode rules

When `RUNNER_MODE=ci`:

- Any prompt must fail fast with a non-zero exit code.
- Scripts require explicit inputs (e.g., `IMAGE=...`, `SNAPSHOT_DIR=...`).
- Do not rely on terminal interaction or selection menus.

## Operator mode rules

When `RUNNER_MODE=operator`:

- Interactive selection is allowed if guardrails permit it.
- Destructive actions still require explicit flags and approvals.

## Recommended usage

```bash
RUNNER_MODE=ci CI=1 make policy.check
RUNNER_MODE=operator make image.upload IMAGE=/path/to/rootfs.tar.gz
```

## Notes

The runner mode is enforced by Make targets and scripts.
If you see a prompt in CI mode, treat it as a bug.
