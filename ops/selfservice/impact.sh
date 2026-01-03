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
    printf '%s' "${inbox}"
    return
  fi
  if [[ -f "${FABRIC_REPO_ROOT}/examples/selfservice/${id}.yml" ]]; then
    printf '%s' "${FABRIC_REPO_ROOT}/examples/selfservice/${id}.yml"
    return
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
import json
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

providers = set()
capacity_entries = []

for change in changes:
    if not isinstance(change, dict):
        continue
    kind = change.get("kind")
    target = change.get("target")
    if kind == "binding" and isinstance(target, str):
        target_path = (repo_root / target).resolve()
        if target_path.exists():
            binding = yaml.safe_load(target_path.read_text())
            for consumer in binding.get("spec", {}).get("consumers", []) or []:
                provider = consumer.get("provider")
                if provider:
                    providers.add(provider)
    if kind == "capacity" and isinstance(target, str):
        target_path = (repo_root / target).resolve()
        if target_path.exists():
            current_doc = yaml.safe_load(target_path.read_text())
        else:
            current_doc = None
        for entry in change.get("changes", []) or []:
            if not isinstance(entry, dict):
                continue
            path = entry.get("path")
            desired = entry.get("value")
            current = resolve_path(current_doc, path) if current_doc is not None else None
            delta = None
            if isinstance(current, (int, float)) and isinstance(desired, (int, float)):
                delta = desired - current
            capacity_entries.append({
                "path": path,
                "current": current,
                "desired": desired,
                "delta": delta,
            })

risk_levels = ["low", "medium", "high"]

def bump_risk(current, target):
    return risk_levels[max(risk_levels.index(current), risk_levels.index(target))]

slo_risk = "low"
drift_risk = "low"

actions = [c.get("action") for c in changes if isinstance(c, dict)]
if "remove" in actions:
    slo_risk = bump_risk(slo_risk, "high")
    drift_risk = bump_risk(drift_risk, "high")
elif "modify" in actions:
    slo_risk = bump_risk(slo_risk, "medium")
    drift_risk = bump_risk(drift_risk, "medium")

if any(isinstance(c, dict) and c.get("kind") == "exposure_request" for c in changes):
    slo_risk = bump_risk(slo_risk, "medium")

if isinstance(proposal.get("target_env"), str) and "prod" in proposal.get("target_env"):
    slo_risk = bump_risk(slo_risk, "high")
    drift_risk = bump_risk(drift_risk, "high")

capacity_total = None
if capacity_entries:
    deltas = [entry["delta"] for entry in capacity_entries if isinstance(entry.get("delta"), (int, float))]
    capacity_total = sum(deltas) if deltas else None

impact = {
    "proposal_id": proposal.get("proposal_id"),
    "tenant_id": proposal.get("tenant_id"),
    "target_env": proposal.get("target_env"),
    "affected_providers": sorted(providers),
    "capacity_delta": {
        "entries": capacity_entries,
        "total": capacity_total,
    },
    "slo_risk": slo_risk,
    "drift_risk": drift_risk,
}

(out_dir / "impact.json").write_text(json.dumps(impact, indent=2, sort_keys=True) + "\n")
PY

printf 'OK: impact generated at %s\n' "${out_dir}"
