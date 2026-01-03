#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  echo "usage: postcheck.sh --tenant <id> --workload <id> --env <env> --out <path>" >&2
}

tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"
out_path="${OUT_PATH:-}"

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

if [[ -z "${tenant}" || -z "${workload}" || -z "${env_name}" || -z "${out_path}" ]]; then
  usage
  exit 2
fi

artifact_root="${FABRIC_REPO_ROOT}/artifacts/exposure/${env_name}/${tenant}/${workload}"
status="not_exposed"
count=0

if [[ -d "${artifact_root}" ]]; then
  count=$(find "${artifact_root}" -type f -name "bundle.json" | wc -l | awk '{print $1}')
  if [[ "${count}" -gt 0 ]]; then
    status="exposed"
  fi
fi

ARTIFACT_ROOT="${artifact_root}" STATUS="${status}" COUNT="${count}" OUT_PATH="${out_path}" \
python3 - <<'PY'
import json
import os
from pathlib import Path

payload = {
    "artifact_root": os.environ["ARTIFACT_ROOT"],
    "status": os.environ["STATUS"],
    "bundle_count": int(os.environ["COUNT"]),
}

out_path = Path(os.environ["OUT_PATH"])
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY
