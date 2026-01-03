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

risk = "low"
execution = "read-only"
if any(isinstance(c, dict) and c.get("action") == "remove" for c in changes):
    risk = "high"
    execution = "apply"
elif any(isinstance(c, dict) and c.get("action") in {"add", "modify"} for c in changes):
    risk = "medium"
    execution = "apply"

impact = {
    "proposal_id": proposal.get("proposal_id"),
    "tenant_id": proposal.get("tenant_id"),
    "risk": risk,
    "execution_class": execution,
    "affected": [
        {
            "action": c.get("action"),
            "kind": c.get("kind"),
            "target": c.get("target"),
        }
        for c in changes if isinstance(c, dict)
    ],
}

(out_dir / "impact.json").write_text(json.dumps(impact, indent=2, sort_keys=True) + "\n")
PY

printf 'OK: impact generated at %s\n' "${out_dir}"
