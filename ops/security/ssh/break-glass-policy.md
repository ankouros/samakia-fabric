# Break-Glass SSH Key Policy

Purpose:
- Provide emergency access when standard operator keys are unavailable.
- Break-glass keys are a last resort and must be auditable.

Rules:
- Break-glass keys are **separate** from operator keys.
- Rotation requires explicit operator intent:
  - `BREAK_GLASS=1`
  - `I_UNDERSTAND=1`
- Break-glass keys must never be committed to Git.
- Private keys live only on the runner under `~/.config/samakia-fabric/`.

Custody:
- Two-person rule is recommended for break-glass key custody.
- Document who holds each key and when it was last rotated.

Operational notes:
- Break-glass rotation should be staged and verified.
- After emergency use, rotate break-glass keys immediately.
- Root SSH remains disabled; break-glass keys apply to the operator account only.
