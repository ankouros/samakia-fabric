#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ -z "${TENANT:-}" ]]; then
  echo "ERROR: TENANT is required" >&2
  exit 2
fi

if [[ -z "${DRIFT_OUT:-}" || -z "${VERIFY_OUT:-}" ]]; then
  echo "ERROR: DRIFT_OUT and VERIFY_OUT are required" >&2
  exit 2
fi

drift_root="${DRIFT_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/drift}"
verify_root="${VERIFY_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/bindings-verify}"
tenant_root="${TENANT_EVIDENCE_ROOT:-${FABRIC_REPO_ROOT}/evidence/tenants}"

python3 - "${TENANT}" "${WORKLOAD:-}" "${drift_root}" "${verify_root}" "${tenant_root}" "${DRIFT_OUT}" "${VERIFY_OUT}" "${FABRIC_REPO_ROOT}" <<'PY'
import json
import sys
from pathlib import Path

tenant = sys.argv[1]
workload = sys.argv[2]
drift_root = Path(sys.argv[3])
verify_root = Path(sys.argv[4])
tenant_root = Path(sys.argv[5])
drift_out = Path(sys.argv[6])
verify_out = Path(sys.argv[7])
repo_root = Path(sys.argv[8])


def rel(path: Path):
    try:
        return str(path.relative_to(repo_root))
    except ValueError:
        return str(path)


def latest_dir(base: Path):
    if not base.exists():
        return None
    dirs = sorted([p for p in base.iterdir() if p.is_dir()])
    return dirs[-1] if dirs else None


def latest_nested_dir(base: Path, subdir: str):
    if not base.exists():
        return None
    candidates = []
    for p in base.iterdir():
        if not p.is_dir():
            continue
        nested = p / subdir
        if nested.exists():
            candidates.append(p)
    if not candidates:
        return None
    return sorted(candidates)[-1]


def load_json(path: Path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


# Drift + capacity

drift_payload = {
    "tenant": tenant,
    "workload": workload or None,
    "drift": {
        "status": "MISSING",
        "class": "unknown",
        "severity": "info",
        "timestamp": None,
        "source": None,
        "available": False,
    },
    "capacity": {
        "status": "MISSING",
        "violations": [],
        "timestamp": None,
        "source": None,
        "available": False,
    },
}

latest_drift = latest_dir(drift_root / tenant)
if latest_drift:
    classification_path = latest_drift / "classification.json"
    classification = load_json(classification_path)
    if isinstance(classification, dict):
        overall = classification.get("overall", {})
        drift_payload["drift"] = {
            "status": overall.get("status", "UNKNOWN"),
            "class": overall.get("class", "unknown"),
            "severity": overall.get("severity", "info"),
            "timestamp": classification.get("timestamp"),
            "source": rel(classification_path),
            "available": True,
        }

latest_capacity_parent = latest_nested_dir(tenant_root / tenant, "substrate-capacity")
if latest_capacity_parent:
    decision_path = latest_capacity_parent / "substrate-capacity" / "decision.json"
    decision = load_json(decision_path)
    if isinstance(decision, dict):
        drift_payload["capacity"] = {
            "status": decision.get("status", "UNKNOWN"),
            "violations": decision.get("violations", []),
            "timestamp": None,
            "source": rel(decision_path),
            "available": True,
        }


def extract_checks(result):
    checks = []
    raw = result.get("checks", {}) if isinstance(result, dict) else {}
    if isinstance(raw, dict):
        for name, check in raw.items():
            if not isinstance(check, dict):
                continue
            checks.append({
                "name": name,
                "status": check.get("status"),
                "message": check.get("message"),
            })
    return checks


verify_payload = {
    "tenant": tenant,
    "workload": workload or None,
    "bindings_verify": {
        "status": "MISSING",
        "mode": None,
        "checks": [],
        "source": None,
        "available": False,
    },
    "substrate_observe": {
        "status": "MISSING",
        "limitations": [],
        "timestamp": None,
        "source": None,
        "available": False,
    },
}

latest_verify = latest_dir(verify_root / tenant)
if latest_verify:
    per_binding = None
    if workload:
        per_binding = latest_verify / "per-binding" / f"{workload}.json"
    results_path = latest_verify / "results.json"
    data = None
    if per_binding and per_binding.exists():
        data = load_json(per_binding)
        source_path = per_binding
    elif results_path.exists():
        data = load_json(results_path)
        source_path = results_path
    else:
        data = None
        source_path = None

    if data is not None:
        entries = data if isinstance(data, list) else [data]
        selected = None
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            if workload and entry.get("workload_id") not in (workload, None):
                continue
            selected = entry
            break
        if selected:
            results = selected.get("results", [])
            checks = []
            mode = selected.get("mode")
            for result in results:
                checks.extend(extract_checks(result))
                if not mode:
                    mode = result.get("mode")
            verify_payload["bindings_verify"] = {
                "status": selected.get("status", "UNKNOWN"),
                "mode": mode,
                "checks": checks,
                "source": rel(source_path) if source_path else None,
                "available": True,
            }

latest_observe_parent = latest_nested_dir(tenant_root / tenant, "substrate-observe")
if latest_observe_parent:
    decision_path = latest_observe_parent / "substrate-observe" / "decision.json"
    decision = load_json(decision_path)
    if isinstance(decision, dict):
        verify_payload["substrate_observe"] = {
            "status": decision.get("status", "UNKNOWN"),
            "limitations": decision.get("limitations", []),
            "timestamp": decision.get("timestamp_utc"),
            "source": rel(decision_path),
            "available": True,
        }


drift_out.write_text(json.dumps(drift_payload, indent=2, sort_keys=True) + "\n")
verify_out.write_text(json.dumps(verify_payload, indent=2, sort_keys=True) + "\n")
PY
