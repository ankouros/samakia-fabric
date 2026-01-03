#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  echo "usage: generate.sh --tenant <id> --workload <id> --env <env> --policy <path> --decision <path> --plan <path> --diff <path>" >&2
}

policy_path=""
decision_path=""
plan_path=""
diff_path=""
tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy)
      policy_path="$2"
      shift 2
      ;;
    --decision)
      decision_path="$2"
      shift 2
      ;;
    --plan)
      plan_path="$2"
      shift 2
      ;;
    --diff)
      diff_path="$2"
      shift 2
      ;;
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

if [[ -z "${tenant}" || -z "${workload}" || -z "${env_name}" || -z "${policy_path}" || -z "${decision_path}" || -z "${plan_path}" || -z "${diff_path}" ]]; then
  usage
  exit 2
fi

for file in "${policy_path}" "${decision_path}" "${plan_path}" "${diff_path}"; do
  if [[ ! -f "${file}" ]]; then
    echo "ERROR: input file not found: ${file}" >&2
    exit 1
  fi
done

stamp="${EVIDENCE_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
out_dir="${EVIDENCE_DIR:-${FABRIC_REPO_ROOT}/evidence/exposure-plan/${tenant}/${workload}/${stamp}}"

POLICY_PATH="${policy_path}" DECISION_PATH="${decision_path}" PLAN_PATH="${plan_path}" \
OUT_DIR="${out_dir}" TENANT="${tenant}" WORKLOAD="${workload}" ENV_NAME="${env_name}" \
python3 - <<'PY'
import json
import os
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: PyYAML required: {exc}")

policy_path = Path(os.environ["POLICY_PATH"])
decision_path = Path(os.environ["DECISION_PATH"])
plan_path = Path(os.environ["PLAN_PATH"])

out_dir = Path(os.environ["OUT_DIR"])
tenant = os.environ["TENANT"]
workload = os.environ["WORKLOAD"]
env_name = os.environ["ENV_NAME"]

out_dir.mkdir(parents=True, exist_ok=True)

policy = yaml.safe_load(policy_path.read_text())
policy_json = json.dumps(policy, indent=2, sort_keys=True) + "\n"
(out_dir / "policy.json").write_text(policy_json)

(out_dir / "decision.json").write_text(decision_path.read_text())
(out_dir / "plan.json").write_text(plan_path.read_text())

summary_lines = [
    "# Exposure Plan Summary",
    "",
    f"Tenant: {tenant}",
    f"Workload: {workload}",
    f"Env: {env_name}",
    f"Allowed: {json.loads(decision_path.read_text()).get('allowed')}",
    "",
    "Statement:",
    "Exposure planning only; no exposure artifacts were applied.",
]
(out_dir / "summary.md").write_text("\n".join(summary_lines) + "\n")
PY

cp "${diff_path}" "${out_dir}/diff.md"

bash "${FABRIC_REPO_ROOT}/ops/exposure/evidence/manifest.sh" "${out_dir}"
bash "${FABRIC_REPO_ROOT}/ops/exposure/evidence/sign.sh" "${env_name}" "${out_dir}"

echo "${out_dir}"
