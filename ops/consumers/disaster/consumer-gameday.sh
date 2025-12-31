#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

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
if [[ ! -f "${registry_path}" ]]; then
  echo "ERROR: disaster testcases registry not found: ${registry_path}" >&2
  exit 1
fi

if [[ ! -f "${CONSUMER_PATH}" ]]; then
  echo "ERROR: consumer contract not found: ${CONSUMER_PATH}" >&2
  exit 1
fi

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
  baseline_report="$(bash "${FABRIC_REPO_ROOT}/ops/scripts/gameday/gameday-evidence.sh" --id "${gameday_id}" --tag baseline)"
fi

action_summary="read-only"

if [[ "${TESTCASE_MODE}" == "safe-gameday" ]]; then
  if [[ "${MODE}" == "execute" ]]; then
    if [[ "${GAMEDAY_EXECUTE:-}" != "1" ]]; then
      echo "ERROR: execution requires GAMEDAY_EXECUTE=1" >&2
      exit 1
    fi
  fi

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
  "timestamp_utc": "${stamp}"
}
META

sha_report="$(sha256sum "${report_path}" | awk '{print $1}')"
sha_meta="$(sha256sum "${metadata_path}" | awk '{print $1}')"

cat <<MANIFEST > "${manifest_path}"
${sha_report}  report.md
${sha_meta}  metadata.json
MANIFEST

printf "OK: gameday evidence -> %s\n" "${evidence_dir}"
