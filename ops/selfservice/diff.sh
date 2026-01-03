#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


proposal_id="${PROPOSAL_ID:-}"
file_override="${FILE:-}"

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

out_dir="${OUT_DIR:-$(mktemp -d)}"
mkdir -p "${out_dir}"

PROPOSAL_PATH="${proposal_path}" OUT_DIR="${out_dir}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - <<'PY'
import os
from pathlib import Path
import yaml

proposal_path = Path(os.environ["PROPOSAL_PATH"])
repo_root = Path(os.environ["FABRIC_REPO_ROOT"])
out_dir = Path(os.environ["OUT_DIR"])

proposal = yaml.safe_load(proposal_path.read_text())
changes = proposal.get("desired_changes", []) if isinstance(proposal, dict) else []


def resolve_path(data, path):
    current = data
    for part in path.split("."):
        if isinstance(current, list) and part.isdigit():
            idx = int(part)
            if idx < 0 or idx >= len(current):
                return None
            current = current[idx]
        elif isinstance(current, dict) and part in current:
            current = current[part]
        else:
            return None
    return current

lines = [
    f"Proposal: {proposal.get('proposal_id')}",
    f"Tenant: {proposal.get('tenant_id')}",
    f"Target env: {proposal.get('target_env')}",
    "",
    "Changes:",
]

for change in changes:
    if not isinstance(change, dict):
        continue
    kind = change.get("kind")
    action = change.get("action")
    target = change.get("target")
    lines.append(f"- {kind} {action}: {target}")

    if kind in {"binding", "capacity"}:
        target_path = (repo_root / target).resolve() if isinstance(target, str) else None
        if target_path and target_path.exists():
            current_doc = yaml.safe_load(target_path.read_text())
        else:
            current_doc = None
            lines.append("  - current: target not found")

        changes_list = change.get("changes", []) if isinstance(change.get("changes"), list) else []
        for entry in changes_list:
            path = entry.get("path") if isinstance(entry, dict) else None
            desired = entry.get("value") if isinstance(entry, dict) else None
            if not path:
                continue
            current = resolve_path(current_doc, path) if current_doc is not None else None
            lines.append(f"  - {path}: {current} -> {desired}")

    if kind == "exposure_request":
        exposure = change.get("exposure", {}) if isinstance(change.get("exposure"), dict) else {}
        workload = exposure.get("workload")
        if workload:
            lines.append(f"  - workload: {workload}")

(out_dir / "diff.md").write_text("\n".join(lines) + "\n")
PY

printf 'OK: diff generated at %s\n' "${out_dir}"
