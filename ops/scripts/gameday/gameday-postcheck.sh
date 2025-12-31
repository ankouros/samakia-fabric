#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  gameday-postcheck.sh [--id <gameday-id>]

Read-only postchecks for GameDay runs.
EOT
}

GAMEDAY_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)
      GAMEDAY_ID="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${GAMEDAY_ID}" ]]; then
  GAMEDAY_ID="gameday-$(date -u +%Y%m%dT%H%M%SZ)"
fi

post_path="$(bash "${FABRIC_REPO_ROOT}/ops/scripts/gameday/gameday-evidence.sh" --id "${GAMEDAY_ID}" --tag post)"

baseline_dir="${FABRIC_REPO_ROOT}/artifacts/gameday/${GAMEDAY_ID}/baseline"
post_dir="${FABRIC_REPO_ROOT}/artifacts/gameday/${GAMEDAY_ID}/post"
if [[ -f "${baseline_dir}/report.md" && -f "${post_dir}/report.md" ]]; then
  diff -u "${baseline_dir}/report.md" "${post_dir}/report.md" > "${FABRIC_REPO_ROOT}/artifacts/gameday/${GAMEDAY_ID}/diff.txt" || true
fi

echo "PASS: GameDay postcheck complete (post report: ${post_path})"
