#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  echo "usage: drift-snapshot.sh --tenant <id> --env <env> --out <path>" >&2
}

tenant="${TENANT:-}"
env_name="${ENV:-}"
out_path="${OUT_PATH:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)
      tenant="$2"
      shift 2
      ;;
    --env)
      env_name="$2"
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

if [[ -z "${tenant}" || -z "${env_name}" || -z "${out_path}" ]]; then
  usage
  exit 2
fi

if [[ "${env_name}" == "samakia-prod" && "${EXPOSE_SIGN:-0}" == "1" ]]; then
  if [[ -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
    echo "ERROR: EVIDENCE_SIGN_KEY is required for prod drift evidence" >&2
    exit 2
  fi
fi

before="${FABRIC_REPO_ROOT}/evidence/drift/${tenant}"
mkdir -p "${before}"

ENV="${env_name}" DRIFT_OFFLINE=1 DRIFT_NON_BLOCKING=1 DRIFT_FAIL_ON=none \
EVIDENCE_SIGN="${EXPOSE_SIGN:-0}" EVIDENCE_SIGN_KEY="${EVIDENCE_SIGN_KEY:-}" \
  make -C "${FABRIC_REPO_ROOT}" drift.detect TENANT="${tenant}"

ENV="${env_name}" make -C "${FABRIC_REPO_ROOT}" drift.summary TENANT="${tenant}"

latest="$(find "${before}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n 1)"
if [[ -z "${latest}" ]]; then
  echo "ERROR: drift evidence not found for tenant ${tenant}" >&2
  exit 1
fi

snapshot_dir="${before}/${latest}"
summary_json="${FABRIC_REPO_ROOT}/artifacts/tenant-status/${tenant}/drift-summary.json"
summary_md="${FABRIC_REPO_ROOT}/artifacts/tenant-status/${tenant}/drift-summary.md"

TENANT="${tenant}" ENV_NAME="${env_name}" SNAPSHOT_DIR="${snapshot_dir}" \
SUMMARY_JSON="${summary_json}" SUMMARY_MD="${summary_md}" OUT_PATH="${out_path}" \
python3 - <<'PY'
import json
import os
from pathlib import Path

payload = {
    "tenant": os.environ["TENANT"],
    "env": os.environ["ENV_NAME"],
    "snapshot_dir": os.environ["SNAPSHOT_DIR"],
    "summary_json": os.environ.get("SUMMARY_JSON"),
    "summary_md": os.environ.get("SUMMARY_MD"),
}

out_path = Path(os.environ["OUT_PATH"])
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
