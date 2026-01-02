#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

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
  inbox=$(find "${FABRIC_REPO_ROOT}/proposals/inbox" -type f -name "proposal.yml" -path "*/${id}/*" 2>/dev/null | head -n1 || true)
  if [[ -n "${inbox}" ]]; then
    printf '%s' "${inbox}"; return
  fi
  if [[ -f "${FABRIC_REPO_ROOT}/examples/proposals/${id}.yml" ]]; then
    printf '%s' "${FABRIC_REPO_ROOT}/examples/proposals/${id}.yml"; return
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

PROPOSAL_PATH="${proposal_path}" OUT_DIR="${out_dir}" python3 - <<'PY'
import json
import os
from pathlib import Path
import yaml

proposal_path = Path(os.environ["PROPOSAL_PATH"])
out_dir = Path(os.environ["OUT_DIR"])

proposal = yaml.safe_load(proposal_path.read_text())
changes = proposal.get("changes", []) if isinstance(proposal, dict) else []

summary = {
    "proposal_id": proposal.get("proposal_id"),
    "tenant_id": proposal.get("tenant_id"),
    "changes": changes,
}

(out_dir / "diff.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")

lines = [
    f"Proposal: {proposal.get('proposal_id')}",
    f"Tenant: {proposal.get('tenant_id')}",
    "",
    "Changes:",
]
for change in changes:
    if isinstance(change, dict):
        lines.append(f"- {change.get('action')} {change.get('kind')}: {change.get('target')}")

(out_dir / "diff.md").write_text("\n".join(lines) + "\n")
PY

printf 'OK: diff generated at %s\n' "${out_dir}"
