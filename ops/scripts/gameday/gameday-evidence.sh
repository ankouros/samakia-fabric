#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  gameday-evidence.sh [--id <gameday-id>] [--tag baseline|post]

Captures a read-only evidence snapshot and stores it under:
  artifacts/gameday/<GAMEDAY_ID>/<tag>/<UTC>/report.md
EOT
}

GAMEDAY_ID=""
TAG="baseline"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)
      GAMEDAY_ID="${2:-}"
      shift 2
      ;;
    --tag)
      TAG="${2:-}"
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

if [[ "${TAG}" != "baseline" && "${TAG}" != "post" ]]; then
  echo "ERROR: invalid tag: ${TAG} (expected baseline or post)" >&2
  exit 2
fi

bash "${FABRIC_REPO_ROOT}/ops/scripts/ha/evidence-snapshot.sh"

latest_dir="$(find "${FABRIC_REPO_ROOT}/artifacts/ha-evidence" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n 1)"
if [[ -z "${latest_dir}" ]]; then
  echo "ERROR: no ha-evidence snapshots found" >&2
  exit 1
fi

src_report="${FABRIC_REPO_ROOT}/artifacts/ha-evidence/${latest_dir}/report.md"
if [[ ! -f "${src_report}" ]]; then
  echo "ERROR: missing evidence report: ${src_report}" >&2
  exit 1
fi

dst_dir="${FABRIC_REPO_ROOT}/artifacts/gameday/${GAMEDAY_ID}/${TAG}/${latest_dir}"
mkdir -p "${dst_dir}"
cp "${src_report}" "${dst_dir}/report.md"

printf '%s\n' "${dst_dir}/report.md"
