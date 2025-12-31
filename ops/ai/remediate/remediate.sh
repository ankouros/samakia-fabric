#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  remediate.sh --target <safe-name> [--execute]

Default is dry-run. Execution requires explicit guards:
  AI_REMEDIATE=1
  AI_REMEDIATE_REASON="<text>"
  ENV=<allowlisted env> (dev/staging only)
  MAINT_WINDOW_START=<UTC>
  MAINT_WINDOW_END=<UTC>
  I_UNDERSTAND_MUTATION=1
EOT
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: missing required env var: ${name}" >&2
    exit 1
  fi
}

target=""
execute=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      target="${2:-}"
      shift 2
      ;;
    --execute)
      execute=1
      shift
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

if [[ -z "${target}" ]]; then
  usage
  exit 2
fi

require_cmd date
require_cmd git
require_cmd sha256sum
require_cmd find
require_cmd sort
require_cmd xargs

safe_run="${FABRIC_REPO_ROOT}/ops/scripts/safe-run.sh"
if [[ ! -x "${safe_run}" ]]; then
  echo "ERROR: safe-run wrapper not found or not executable: ${safe_run}" >&2
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
commit_short="$(git -C "${FABRIC_REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

if [[ -z "${ENV:-}" ]]; then
  echo "ERROR: ENV must be set for remediation" >&2
  exit 1
fi

allowed_envs=("samakia-dev" "samakia-staging")
allowed=0
for env in "${allowed_envs[@]}"; do
  if [[ "${ENV}" == "${env}" ]]; then
    allowed=1
    break
  fi
done

if [[ "${execute}" -eq 1 ]]; then
  if [[ "${allowed}" -ne 1 ]]; then
    echo "ERROR: ENV ${ENV} is not allowlisted for remediation" >&2
    exit 1
  fi
  require_env AI_REMEDIATE
  require_env AI_REMEDIATE_REASON
  require_env MAINT_WINDOW_START
  require_env MAINT_WINDOW_END
  require_env I_UNDERSTAND_MUTATION
  if [[ "${AI_REMEDIATE}" != "1" ]]; then
    echo "ERROR: AI_REMEDIATE must be set to 1" >&2
    exit 1
  fi
  if [[ ${#AI_REMEDIATE_REASON} -lt 8 ]]; then
    echo "ERROR: AI_REMEDIATE_REASON must be at least 8 characters" >&2
    exit 1
  fi
  if [[ "${I_UNDERSTAND_MUTATION}" != "1" ]]; then
    echo "ERROR: I_UNDERSTAND_MUTATION must be set to 1" >&2
    exit 1
  fi
  bash "${FABRIC_REPO_ROOT}/ops/scripts/maint-window.sh" \
    --start "${MAINT_WINDOW_START}" --end "${MAINT_WINDOW_END}"
fi

out_dir="${FABRIC_REPO_ROOT}/evidence/ai/remediation/${ENV}/${stamp}"
mkdir -p "${out_dir}"

plan_path="${out_dir}/plan.md"
exec_log="${out_dir}/execution.log"
post_path="${out_dir}/postchecks.md"
manifest_path="${out_dir}/manifest.sha256"

cat <<EOF_PLAN >"${plan_path}"
# AI Remediation Plan

Environment: ${ENV}
Target: ${target}
Mode: $([[ "${execute}" -eq 1 ]] && echo execute || echo dry-run)
Timestamp (UTC): ${stamp}
Commit: ${commit_short}
Reason: ${AI_REMEDIATE_REASON:-<none>}
Maintenance window: ${MAINT_WINDOW_START:-<none>} - ${MAINT_WINDOW_END:-<none>}
EOF_PLAN

if [[ "${execute}" -eq 1 ]]; then
  SAFE_RUN_EXECUTE=1 I_UNDERSTAND_MUTATION=1 \
    "${safe_run}" "${target}" --execute >"${exec_log}" 2>&1
else
  "${safe_run}" "${target}" --dry-run >"${exec_log}" 2>&1
fi

cat <<EOF_POST >"${post_path}"
# Postchecks

- Safe-run wrapper executed for target: ${target}
- Review safe-run evidence packet for detailed output.
EOF_POST

(
  cd "${out_dir}"
  find . -type f ! -name 'manifest.sha256' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >"${manifest_path}"
)

if [[ "${EVIDENCE_SIGN:-0}" == "1" ]]; then
  if [[ -z "${EVIDENCE_GPG_KEY:-}" ]]; then
    echo "ERROR: EVIDENCE_SIGN=1 but EVIDENCE_GPG_KEY is not set" >&2
    exit 1
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg not found; cannot sign evidence" >&2
    exit 1
  fi
  gpg --batch --yes --local-user "${EVIDENCE_GPG_KEY}" \
    --armor --detach-sign "${manifest_path}"
fi

echo "OK: remediation packet written to ${out_dir}"
