#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


proposal_id="${PROPOSAL_ID:-}"
file_override="${FILE:-}"
if [[ -z "${proposal_id}" && -z "${file_override}" ]]; then
  echo "ERROR: set PROPOSAL_ID or FILE" >&2
  exit 1
fi

resolve_file() {
  local id="$1"
  local file="$2"
  if [[ -n "${file}" ]]; then
    printf '%s' "${file}"
    return
  fi
  if [[ -z "${id}" ]]; then
    echo ""; return
  fi
  local inbox
  inbox=$(find "${FABRIC_REPO_ROOT}/selfservice/inbox" -type f -name "proposal.yml" -path "*/${id}/*" 2>/dev/null | head -n1 || true)
  if [[ -n "${inbox}" ]]; then
    printf '%s' "${inbox}"; return
  fi
  if [[ -f "${FABRIC_REPO_ROOT}/examples/selfservice/${id}.yml" ]]; then
    printf '%s' "${FABRIC_REPO_ROOT}/examples/selfservice/${id}.yml"; return
  fi
  echo ""
}

proposal_path="$(resolve_file "${proposal_id}" "${file_override}")"
if [[ -z "${proposal_path}" || ! -f "${proposal_path}" ]]; then
  echo "ERROR: proposal file not found" >&2
  exit 1
fi

read -r tenant_id prop_id target_env < <(PROPOSAL_PATH="${proposal_path}" python3 - <<'PY'
import os
import yaml
from pathlib import Path
proposal = yaml.safe_load(Path(os.environ["PROPOSAL_PATH"]).read_text())
print(proposal.get("tenant_id", ""), proposal.get("proposal_id", ""), proposal.get("target_env", ""))
PY
)

if [[ -z "${tenant_id}" || -z "${prop_id}" ]]; then
  echo "ERROR: proposal missing tenant_id or proposal_id" >&2
  exit 1
fi

evidence_dir="${FABRIC_REPO_ROOT}/evidence/selfservice/${tenant_id}/${prop_id}"
mkdir -p "${evidence_dir}"

VALIDATION_OUT="${evidence_dir}/validation.json" FILE="${proposal_path}" \
  bash "${FABRIC_REPO_ROOT}/ops/selfservice/validate.sh"

OUT_DIR="${evidence_dir}" FILE="${proposal_path}" \
  bash "${FABRIC_REPO_ROOT}/ops/selfservice/diff.sh"

OUT_DIR="${evidence_dir}" FILE="${proposal_path}" \
  bash "${FABRIC_REPO_ROOT}/ops/selfservice/impact.sh"

SKIP_VALIDATE=1 FILE="${proposal_path}" \
  bash "${FABRIC_REPO_ROOT}/ops/selfservice/plan.sh"

cp "${proposal_path}" "${evidence_dir}/proposal.yml"
sha256sum "${evidence_dir}/proposal.yml" | awk '{print $1}' >"${evidence_dir}/proposal.sha256"

SUMMARY_OUT="${evidence_dir}/summary.md" EVIDENCE_DIR="${evidence_dir}" TARGET_ENV="${target_env}" python3 - <<'PY'
import json
import os
from pathlib import Path
import yaml

summary_out = Path(os.environ["SUMMARY_OUT"])
evidence_dir = Path(os.environ["EVIDENCE_DIR"])

proposal = yaml.safe_load((evidence_dir / "proposal.yml").read_text())
validation = json.loads((evidence_dir / "validation.json").read_text())
impact = json.loads((evidence_dir / "impact.json").read_text())
plan = json.loads((evidence_dir / "plan.json").read_text())

lines = [
    "# Self-Service Proposal Review",
    "",
    f"Proposal: {proposal.get('proposal_id')}",
    f"Tenant: {proposal.get('tenant_id')}",
    f"Target env: {proposal.get('target_env')}",
    "",
    "## Validation",
    f"Status: {validation.get('status')}",
]

errors = validation.get("errors") or []
if errors:
    lines.append("Errors:")
    for err in errors:
        lines.append(f"- {err}")
else:
    lines.append("Errors: none")

lines.extend([
    "",
    "## Impact",
    f"Affected providers: {', '.join(impact.get('affected_providers') or []) or 'none'}",
    f"Capacity delta total: {impact.get('capacity_delta', {}).get('total')}",
    f"SLO risk: {impact.get('slo_risk')}",
    f"Drift risk: {impact.get('drift_risk')}",
    "",
    "## Policy Requirements",
])

policy = plan.get("policy_requirements", {})
lines.append(f"Approvals required: {policy.get('approvals_required')}")
lines.append(f"Change window required: {policy.get('change_window_required')}")
lines.append(f"Signing required: {policy.get('signing_required')}")

lines.extend([
    "",
    "## Evidence",
    "- proposal.yml",
    "- validation.json",
    "- diff.md",
    "- impact.json",
    "- plan.json",
    "",
    "Statement: Proposal-only review; no execution performed.",
])

summary_out.write_text("\n".join(lines) + "\n")
PY

manifest_path="${evidence_dir}/manifest.sha256"
find "${evidence_dir}" -maxdepth 1 -type f \( -name "*.json" -o -name "*.md" -o -name "proposal.yml" \) | \
  sort | xargs sha256sum >"${manifest_path}"

printf 'OK: review bundle generated at %s\n' "${evidence_dir}"
