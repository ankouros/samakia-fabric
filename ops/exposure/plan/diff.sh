#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  echo "usage: diff.sh --plan <plan.json> --out <diff.md>" >&2
}

plan_path=""
out_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)
      plan_path="$2"
      shift 2
      ;;
    --out)
      out_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${plan_path}" || -z "${out_path}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${plan_path}" ]]; then
  echo "ERROR: plan file not found: ${plan_path}" >&2
  exit 1
fi

PLAN_PATH="${plan_path}" OUT_PATH="${out_path}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT:-}" python3 - <<'PY'
import json
import os
from pathlib import Path

plan_path = Path(os.environ["PLAN_PATH"])
out_path = Path(os.environ["OUT_PATH"])
repo_root = os.environ.get("FABRIC_REPO_ROOT") or ""

plan = json.loads(plan_path.read_text())
artifacts = plan.get("artifacts", [])

lines = [
    "# Exposure Plan Diff",
    "",
    "Planned artifacts:",
]
for artifact in artifacts:
    path = artifact.get("path")
    if path:
        lines.append(f"- {path}")

existing = []
for artifact in artifacts:
    path = artifact.get("path")
    if not path:
        continue
    candidate = Path(path)
    if not candidate.is_absolute() and repo_root:
        candidate = Path(repo_root) / candidate
    if candidate.exists():
        existing.append(path)

lines.append("")
lines.append("Existing artifacts:")
if existing:
    for path in sorted(existing):
        lines.append(f"- {path}")
else:
    lines.append("- none (plan-only; no exposure artifacts applied)")

out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text("\n".join(lines) + "\n")
PY
