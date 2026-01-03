# Runner Modes

Samakia Fabric uses a single, explicit runner contract for all automation.

## Modes

- `RUNNER_MODE=ci` (default)
  - Non-interactive.
  - Prompts are forbidden and must fail fast.
  - Missing inputs must fail (no questions asked).

- `RUNNER_MODE=operator` (explicit)
  - Interactive prompts are allowed only where documented.
  - Use this mode only when a workflow explicitly requires input.

## Rules

- Default is `ci` when `RUNNER_MODE` is unset.
- `CI=1` forces `RUNNER_MODE=ci`.
- If it prompts in CI, it is a bug.
- Do not export `RUNNER_MODE=operator` globally; set it per command.

## Usage examples

Non-interactive (default):

```bash
make tf.plan ENV=samakia-prod
```

Explicit operator mode for a documented prompt:

```bash
RUNNER_MODE=operator bash ops/scripts/runner-env-install.sh
```

CI-safe non-interactive path:

```bash
RUNNER_MODE=ci bash ops/scripts/runner-env-install.sh --non-interactive
```

## Guard implementation

All `ops/**/*.sh` scripts source `ops/runner/guard.sh` and declare their
required mode with `require_ci_mode` or `require_operator_mode`.
