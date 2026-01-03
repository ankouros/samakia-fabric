#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  consumer-gameday.sh --consumer <contract.yml> --testcase <name> [--dry-run|--execute]
                      [--vip-group <group>] [--service <name>] [--target <ip>] [--check-url <url>]

Default mode is --dry-run. Execute requires GAMEDAY_EXECUTE=1.
Destructive modes additionally require GAMEDAY_DESTRUCTIVE=1 and I_UNDERSTAND=1.
EOT
}

CONSUMER_PATH=""
TESTCASE=""
MODE="dry-run"
VIP_GROUP_OVERRIDE=""
SERVICE_OVERRIDE=""
TARGET_OVERRIDE=""
CHECK_URL_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --consumer)
      CONSUMER_PATH="${2:-}"
      shift 2
      ;;
    --testcase)
      TESTCASE="${2:-}"
      shift 2
      ;;
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --execute)
      MODE="execute"
      shift
      ;;
    --vip-group)
      VIP_GROUP_OVERRIDE="${2:-}"
      shift 2
      ;;
    --service)
      SERVICE_OVERRIDE="${2:-}"
      shift 2
      ;;
    --target)
      TARGET_OVERRIDE="${2:-}"
      shift 2
      ;;
    --check-url)
      CHECK_URL_OVERRIDE="${2:-}"
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

if [[ -z "${CONSUMER_PATH}" || -z "${TESTCASE}" ]]; then
  echo "ERROR: --consumer and --testcase are required" >&2
  usage
  exit 2
fi

registry_path="${FABRIC_REPO_ROOT}/ops/consumers/disaster/disaster-testcases.yml"
policy_path="${FABRIC_REPO_ROOT}/ops/consumers/disaster/execute-policy.yml"
if [[ ! -f "${registry_path}" ]]; then
  echo "ERROR: disaster testcases registry not found: ${registry_path}" >&2
  exit 1
fi

if [[ ! -f "${CONSUMER_PATH}" ]]; then
  echo "ERROR: consumer contract not found: ${CONSUMER_PATH}" >&2
  exit 1
fi

if [[ ! -f "${policy_path}" ]]; then
  echo "ERROR: execute policy not found: ${policy_path}" >&2
  exit 1
fi

policy_env="$(POLICY_PATH="${policy_path}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path

policy = json.loads(Path(os.environ["POLICY_PATH"]).read_text())
allowlist = policy.get("allowlist", {})

def emit(key, value):
    print(f"{key}={shlex.quote(str(value))}")

emit("POLICY_ENVS", ",".join(allowlist.get("envs", [])))
emit("POLICY_ACTIONS", ",".join(allowlist.get("actions", [])))
emit("POLICY_TYPES", ",".join(allowlist.get("consumer_types", [])))
emit("POLICY_VIP_GROUPS", ",".join(allowlist.get("vip_groups", [])))
emit("POLICY_MAX_MINUTES", policy.get("maintenance_window", {}).get("max_minutes", 60))
emit("POLICY_REASON_MIN", policy.get("reason_min_length", 12))
signing = policy.get("signing", {})
emit("POLICY_REQUIRE_SIGN", int(signing.get("require_execute_signing", False)))
emit("POLICY_ALLOW_UNSIGNED", int(signing.get("allow_unsigned_execute", False)))
PY
)" || exit 1

eval "${policy_env}"

info_env="$(CONSUMER_PATH="${CONSUMER_PATH}" TESTCASE="${TESTCASE}" REGISTRY_PATH="${registry_path}" python3 - <<'PY'
import json
import os
import shlex
import sys
from pathlib import Path

contract = json.loads(Path(os.environ["CONSUMER_PATH"]).read_text())
registry = json.loads(Path(os.environ["REGISTRY_PATH"]).read_text())

spec = contract.get("spec", {})
name = contract.get("metadata", {}).get("name", "unknown")
consumer_type = spec.get("type", "unknown")
variant = spec.get("variant", "unknown")

refs = set()
for scenario in spec.get("disaster", {}).get("scenarios", []):
    for testcase in scenario.get("testcases", []):
        refs.add(testcase)

requested = os.environ["TESTCASE"]
if requested not in refs:
    print(f"ERROR: testcase {requested} not referenced by consumer contract", file=sys.stderr)
    sys.exit(2)

entry = registry.get("testcases", {}).get(requested)
if entry is None:
    print(f"ERROR: testcase {requested} not found in registry", file=sys.stderr)
    sys.exit(2)

mode = entry.get("mode", "read-only")
action = entry.get("gameday_action", "")
defaults = entry.get("default_inputs", {}) or {}

def emit(key, value):
    if value is None:
        return
    print(f"{key}={shlex.quote(str(value))}")

emit("CONSUMER_NAME", name)
emit("CONSUMER_TYPE", consumer_type)
emit("CONSUMER_VARIANT", variant)
emit("TESTCASE_MODE", mode)
emit("GAMEDAY_ACTION", action)

for key, value in defaults.items():
    emit(f"DEFAULT_{key}", value)
PY
)" || exit 1

eval "${info_env}"

VIP_GROUP="${VIP_GROUP_OVERRIDE:-${DEFAULT_VIP_GROUP:-}}"
SERVICE="${SERVICE_OVERRIDE:-${DEFAULT_SERVICE:-}}"
TARGET="${TARGET_OVERRIDE:-${DEFAULT_TARGET:-}}"
CHECK_URL="${CHECK_URL_OVERRIDE:-${DEFAULT_CHECK_URL:-}}"

env_allowed="false"
action_allowed="false"
type_allowed="false"
vip_group_allowed="true"

if [[ -n "${ENV:-}" ]]; then
  if [[ ",${POLICY_ENVS}," == *",${ENV},"* ]]; then
    env_allowed="true"
  fi
fi

if [[ -n "${GAMEDAY_ACTION:-}" ]]; then
  if [[ ",${POLICY_ACTIONS}," == *",${GAMEDAY_ACTION},"* ]]; then
    action_allowed="true"
  fi
fi

if [[ -n "${CONSUMER_TYPE:-}" ]]; then
  if [[ ",${POLICY_TYPES}," == *",${CONSUMER_TYPE},"* ]]; then
    type_allowed="true"
  fi
fi

if [[ -n "${POLICY_VIP_GROUPS:-}" && -n "${VIP_GROUP:-}" ]]; then
  vip_group_allowed="false"
  if [[ ",${POLICY_VIP_GROUPS}," == *",${VIP_GROUP},"* ]]; then
    vip_group_allowed="true"
  fi
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"

evidence_dir="${FABRIC_REPO_ROOT}/evidence/consumers/gameday/${CONSUMER_NAME}/${TESTCASE}/${stamp}"
mkdir -p "${evidence_dir}"

report_path="${evidence_dir}/report.md"
metadata_path="${evidence_dir}/metadata.json"
manifest_path="${evidence_dir}/manifest.sha256"

gameday_id="consumer-${CONSUMER_NAME}-${TESTCASE}"

bash "${FABRIC_REPO_ROOT}/ops/scripts/gameday/gameday-precheck.sh"

baseline_report="dry-run (skipped)"
post_report="dry-run (skipped)"

if [[ "${MODE}" == "execute" ]]; then
  if [[ "${GAMEDAY_EXECUTE:-}" != "1" ]]; then
    echo "ERROR: execution requires GAMEDAY_EXECUTE=1" >&2
    exit 1
  fi
  if [[ "${I_UNDERSTAND_MUTATION:-}" != "1" ]]; then
    echo "ERROR: execution requires I_UNDERSTAND_MUTATION=1" >&2
    exit 1
  fi
  if [[ -z "${ENV:-}" ]]; then
    echo "ERROR: execution requires ENV to be set" >&2
    exit 1
  fi
  if [[ "${TESTCASE_MODE}" != "safe-gameday" ]]; then
    echo "ERROR: execute mode is only allowed for safe-gameday testcases" >&2
    exit 1
  fi
  if [[ "${env_allowed}" != "true" ]]; then
    echo "ERROR: ENV ${ENV} not allowlisted for execute mode" >&2
    exit 1
  fi
  if [[ "${action_allowed}" != "true" ]]; then
    echo "ERROR: action ${GAMEDAY_ACTION} not allowlisted for execute mode" >&2
    exit 1
  fi
  if [[ "${type_allowed}" != "true" ]]; then
    echo "ERROR: consumer type ${CONSUMER_TYPE} not allowlisted for execute mode" >&2
    exit 1
  fi
  if [[ "${vip_group_allowed}" != "true" ]]; then
    echo "ERROR: VIP_GROUP ${VIP_GROUP} not allowlisted for execute mode" >&2
    exit 1
  fi
  if [[ -z "${GAMEDAY_REASON:-}" ]]; then
    echo "ERROR: execution requires GAMEDAY_REASON" >&2
    exit 1
  fi
  if [[ ${#GAMEDAY_REASON} -lt ${POLICY_REASON_MIN} ]]; then
    echo "ERROR: GAMEDAY_REASON must be at least ${POLICY_REASON_MIN} characters" >&2
    exit 1
  fi
  if [[ -z "${MAINT_WINDOW_START:-}" || -z "${MAINT_WINDOW_END:-}" ]]; then
    echo "ERROR: execution requires MAINT_WINDOW_START and MAINT_WINDOW_END" >&2
    exit 1
  fi
  bash "${FABRIC_REPO_ROOT}/ops/scripts/maint-window.sh" \
    --start "${MAINT_WINDOW_START}" \
    --end "${MAINT_WINDOW_END}" \
    --max-minutes "${POLICY_MAX_MINUTES}"

  if [[ "${POLICY_REQUIRE_SIGN}" == "1" && "${POLICY_ALLOW_UNSIGNED}" != "1" ]]; then
    if [[ "${EVIDENCE_SIGN:-0}" != "1" || -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
      echo "ERROR: execution requires EVIDENCE_SIGN=1 and EVIDENCE_SIGN_KEY" >&2
      exit 1
    fi
  fi

  baseline_report="$(bash "${FABRIC_REPO_ROOT}/ops/scripts/gameday/gameday-evidence.sh" --id "${gameday_id}" --tag baseline)"
fi

action_summary="read-only"

if [[ "${TESTCASE_MODE}" == "safe-gameday" ]]; then
  case "${GAMEDAY_ACTION}" in
    vip-failover)
      if [[ -z "${VIP_GROUP}" ]]; then
        echo "ERROR: VIP_GROUP is required for vip-failover" >&2
        exit 1
      fi
      bash "${FABRIC_REPO_ROOT}/ops/scripts/gameday/gameday-vip-failover.sh" --vip-group "${VIP_GROUP}" "--${MODE}"
      action_summary="vip-failover (${MODE})"
      ;;
    service-restart)
      if [[ -z "${SERVICE}" || -z "${TARGET}" ]]; then
        echo "ERROR: SERVICE and TARGET are required for service-restart" >&2
        exit 1
      fi
      args=(--service "${SERVICE}" --target "${TARGET}" "--${MODE}")
      if [[ -n "${CHECK_URL}" ]]; then
        args+=(--check-url "${CHECK_URL}")
      fi
      bash "${FABRIC_REPO_ROOT}/ops/scripts/gameday/gameday-service-restart.sh" "${args[@]}"
      action_summary="service-restart (${MODE})"
      ;;
    *)
      echo "ERROR: unsupported gameday action: ${GAMEDAY_ACTION}" >&2
      exit 1
      ;;
  esac
elif [[ "${TESTCASE_MODE}" == "destructive" ]]; then
  if [[ "${MODE}" == "execute" ]]; then
    if [[ "${GAMEDAY_EXECUTE:-}" != "1" || "${GAMEDAY_DESTRUCTIVE:-}" != "1" || "${I_UNDERSTAND:-}" != "1" ]]; then
      echo "ERROR: destructive execution requires GAMEDAY_EXECUTE=1 GAMEDAY_DESTRUCTIVE=1 I_UNDERSTAND=1" >&2
      exit 1
    fi
    echo "ERROR: destructive gameday actions are not implemented in this script" >&2
    exit 1
  fi
  action_summary="destructive (dry-run)"
fi

if [[ "${MODE}" == "execute" ]]; then
  post_report="$(bash "${FABRIC_REPO_ROOT}/ops/scripts/gameday/gameday-evidence.sh" --id "${gameday_id}" --tag post)"
  bash "${FABRIC_REPO_ROOT}/ops/scripts/gameday/gameday-postcheck.sh"
fi

reason_preview=""
reason_len="0"
if [[ -n "${GAMEDAY_REASON:-}" ]]; then
  reason_preview="${GAMEDAY_REASON:0:64}"
  reason_len="${#GAMEDAY_REASON}"
fi

cat <<REPORT > "${report_path}"
# Consumer GameDay Report

- consumer: ${CONSUMER_NAME}
- type: ${CONSUMER_TYPE}
- variant: ${CONSUMER_VARIANT}
- testcase: ${TESTCASE}
- mode: ${TESTCASE_MODE}
- action: ${action_summary}
- timestamp: ${stamp}

## Evidence
- baseline: ${baseline_report}
- post: ${post_report}

## Policy decision
- env: ${ENV:-}
- allowlist env: ${env_allowed}
- allowlist action: ${action_allowed}
- allowlist type: ${type_allowed}
- allowlist VIP group: ${vip_group_allowed}
- maintenance window: ${MAINT_WINDOW_START:-} -> ${MAINT_WINDOW_END:-}
- reason length: ${reason_len}
- reason preview: ${reason_preview}

## Inputs
- VIP_GROUP: ${VIP_GROUP:-}
- SERVICE: ${SERVICE:-}
- TARGET: ${TARGET:-}
- CHECK_URL: ${CHECK_URL:-}
REPORT

cat <<META > "${metadata_path}"
{
  "consumer": "${CONSUMER_NAME}",
  "type": "${CONSUMER_TYPE}",
  "variant": "${CONSUMER_VARIANT}",
  "testcase": "${TESTCASE}",
  "mode": "${TESTCASE_MODE}",
  "action": "${GAMEDAY_ACTION}",
  "execute_env": "${ENV:-}",
  "execute": "${MODE}",
  "timestamp_utc": "${stamp}"
}
META

sha_report="$(sha256sum "${report_path}" | awk '{print $1}')"
sha_meta="$(sha256sum "${metadata_path}" | awk '{print $1}')"

cat <<MANIFEST > "${manifest_path}"
${sha_report}  report.md
${sha_meta}  metadata.json
MANIFEST

if [[ "${EVIDENCE_SIGN:-0}" -eq 1 ]]; then
  if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg not found (required for EVIDENCE_SIGN=1)" >&2
    exit 1
  fi
  gpg_args=(--batch --yes --detach-sign)
  if [[ -n "${EVIDENCE_SIGN_KEY:-}" ]]; then
    gpg_args+=(--local-user "${EVIDENCE_SIGN_KEY}")
  fi
  gpg "${gpg_args[@]}" --output "${manifest_path}.asc" "${manifest_path}"
fi

printf "OK: gameday evidence -> %s\n" "${evidence_dir}"
