#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  echo "usage: evidence.sh --tenant <id> --workload <id> --env <env> --rollback <rollback.json> --drift <drift.json> --decision <decision.json>" >&2
}

tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"
rollback_file=""
drift_file=""
decision_file=""
postcheck_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)
      tenant="$2"
      shift 2
      ;;
    --workload)
      workload="$2"
      shift 2
      ;;
    --env)
      env_name="$2"
      shift 2
      ;;
    --rollback)
      rollback_file="$2"
      shift 2
      ;;
    --drift)
      drift_file="$2"
      shift 2
      ;;
    --decision)
      decision_file="$2"
      shift 2
      ;;
    --postcheck)
      postcheck_file="$2"
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

if [[ -z "${tenant}" || -z "${workload}" || -z "${env_name}" || -z "${rollback_file}" || -z "${drift_file}" || -z "${decision_file}" ]]; then
  usage
  exit 2
fi

for path in "${rollback_file}" "${drift_file}" "${decision_file}"; do
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: input file not found: ${path}" >&2
    exit 1
  fi
done

stamp="${EVIDENCE_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
out_dir="${EVIDENCE_DIR:-${FABRIC_REPO_ROOT}/evidence/exposure-rollback/${tenant}/${workload}/${stamp}}"

mkdir -p "${out_dir}"
cp "${rollback_file}" "${out_dir}/rollback.json"
cp "${drift_file}" "${out_dir}/drift.json"
cp "${decision_file}" "${out_dir}/decision.json"

if [[ -n "${postcheck_file}" && -f "${postcheck_file}" ]]; then
  cp "${postcheck_file}" "${out_dir}/postcheck.json"
fi

bash "${FABRIC_REPO_ROOT}/ops/exposure/evidence/manifest.sh" "${out_dir}"
EXPOSURE_SIGN="${EXPOSE_SIGN:-0}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/evidence/sign.sh" "${env_name}" "${out_dir}"

echo "${out_dir}"
