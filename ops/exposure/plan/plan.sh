#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  plan.sh --tenant <id> --workload <id> --env <env>

Notes:
  - Read-only plan; produces evidence and does not write exposure artifacts.
  - Use EXPECT_DENY=1 to treat a denied decision as a success.
EOT
}

tenant="${TENANT:-}"
workload="${WORKLOAD:-}"
env_name="${ENV:-}"

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

if [[ -z "${tenant}" || -z "${workload}" || -z "${env_name}" ]]; then
  usage
  exit 2
fi

# Guard against execute flags in plan-only mode.
guarded_flags=(
  EXPOSE_EXECUTE
  EXPOSE_APPLY
  APPLY_EXECUTE
  ROLLBACK_EXECUTE
  VERIFY_LIVE
  MATERIALIZE_EXECUTE
  ROTATE_EXECUTE
  BIND_EXECUTE
  PROPOSAL_APPLY
)
for flag in "${guarded_flags[@]}"; do
  if [[ "${!flag:-0}" == "1" ]]; then
    echo "ERROR: plan-only mode; ${flag}=1 is not allowed" >&2
    exit 2
  fi
done

policy_file="${POLICY_FILE:-${FABRIC_REPO_ROOT}/contracts/exposure/exposure-policy.yml}"
binding_manifest="${BINDING_MANIFEST:-${FABRIC_REPO_ROOT}/artifacts/bindings/${tenant}/${workload}/connection.json}"
decision_file=""
plan_file=""
diff_file=""

cleanup() {
  rm -f "${decision_file}" "${plan_file}" "${diff_file}"
}
trap cleanup EXIT

if [[ ! -f "${binding_manifest}" ]]; then
  echo "ERROR: binding manifest not found: ${binding_manifest}" >&2
  echo "Hint: run 'make bindings.render TENANT=all'" >&2
  exit 1
fi

bash "${FABRIC_REPO_ROOT}/ops/exposure/policy/validate.sh" --policy "${policy_file}"

mapfile -t plan_info < <(BINDING_MANIFEST="${binding_manifest}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

binding_path = Path(os.environ["BINDING_MANIFEST"])

payload = json.loads(binding_path.read_text())
consumers = payload.get("consumers", [])

providers = []
variants = []
errors = []

for consumer in consumers:
    provider = consumer.get("provider")
    variant = consumer.get("variant")
    if provider and provider not in providers:
        providers.append(provider)
    if variant and variant not in variants:
        variants.append(variant)

    endpoint = consumer.get("endpoint", {})
    if endpoint.get("tls_required") is not True:
        errors.append("tls_required false")
    protocol = endpoint.get("protocol")
    if isinstance(protocol, str) and protocol.lower() in {"http", "plaintext"}:
        errors.append("plaintext protocol")

if errors:
    for err in sorted(set(errors)):
        print(f"ERROR: exposure plan requires TLS-only endpoints ({err})", file=sys.stderr)
    sys.exit(1)

print(",".join(providers))
print(",".join(variants))
PY
)

providers="${plan_info[0]:-}"
variants="${plan_info[1]:-}"

if [[ -z "${providers}" || -z "${variants}" ]]; then
  echo "ERROR: no providers or variants found in binding manifest" >&2
  exit 1
fi

decision_file="$(mktemp)"
TENANT="${tenant}" WORKLOAD="${workload}" ENV="${env_name}" PROVIDERS="${providers}" VARIANTS="${variants}" \
  DECISION_OUT="${decision_file}" POLICY_FILE="${policy_file}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/policy/evaluate.sh"

plan_file="$(mktemp)"
bash "${FABRIC_REPO_ROOT}/ops/exposure/plan/render.sh" \
  --binding "${binding_manifest}" \
  --out "${plan_file}" \
  --tenant "${tenant}" \
  --workload "${workload}" \
  --env "${env_name}"

diff_file="$(mktemp)"
bash "${FABRIC_REPO_ROOT}/ops/exposure/plan/diff.sh" --plan "${plan_file}" --out "${diff_file}"

evidence_dir=$(TENANT="${tenant}" WORKLOAD="${workload}" ENV="${env_name}" \
  bash "${FABRIC_REPO_ROOT}/ops/exposure/evidence/generate.sh" \
  --tenant "${tenant}" --workload "${workload}" --env "${env_name}" \
  --policy "${policy_file}" --decision "${decision_file}" --plan "${plan_file}" --diff "${diff_file}")

echo "PASS plan: evidence -> ${evidence_dir}"

allowed=$(DECISION_FILE="${decision_file}" python3 - <<'PY'
import json
import os

with open(os.environ["DECISION_FILE"], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print("true" if data.get("allowed") else "false")
PY
)

if [[ "${EXPECT_DENY:-0}" == "1" ]]; then
  if [[ "${allowed}" == "true" ]]; then
    echo "ERROR: expected deny but policy allowed" >&2
    exit 1
  fi
  exit 0
fi

if [[ "${allowed}" != "true" ]]; then
  echo "DENY: exposure policy did not allow this plan" >&2
  exit 1
fi
