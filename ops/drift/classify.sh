#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  echo "usage: classify.sh --input <diff.json> --output <classification.json> --tenant <tenant>" >&2
}

input=""
output=""
tenant=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      input="$2"
      shift 2
      ;;
    --output)
      output="$2"
      shift 2
      ;;
    --tenant)
      tenant="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument $1" >&2
      usage
      exit 2
      ;;
  esac
 done

if [[ -z "${tenant}" ]]; then
  usage
  exit 2
fi

if [[ -z "${input}" || -z "${output}" ]]; then
  base="${FABRIC_REPO_ROOT}/evidence/drift/${tenant}"
  if [[ -d "${base}" ]]; then
    latest="$(find "${base}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n 1)"
    if [[ -n "${latest:-}" ]]; then
      input="${input:-${base}/${latest}/diff.json}"
      output="${output:-${base}/${latest}/classification.json}"
    fi
  fi
fi

if [[ -z "${input}" || -z "${output}" ]]; then
  usage
  exit 2
fi

python3 - "${input}" "${output}" "${tenant}" <<'PY'
import json
import sys
from datetime import datetime

input_path = sys.argv[1]
output_path = sys.argv[2]
tenant = sys.argv[3]

payload = json.loads(open(input_path).read())

sources = {
    "configuration": payload.get("bindings", {}),
    "capacity": payload.get("capacity", {}),
    "security": payload.get("security", {}),
    "availability": payload.get("availability", {}),
}

signals = []

class_owners = {
    "configuration": "tenant",
    "capacity": "tenant",
    "security": "operator",
    "availability": "tenant",
    "unknown": "tenant",
    "expected": "tenant",
    "none": "tenant",
}

severity_rank = {"info": 0, "warn": 1, "critical": 2}

# Map statuses to signals
if sources["security"].get("status") == "FAIL":
    signals.append({
        "class": "security",
        "severity": "critical",
        "status": "FAIL",
        "owner": class_owners["security"],
        "summary": "Secret-like material or policy violation detected",
    })

availability_status = sources["availability"].get("status")
if availability_status == "FAIL":
    signals.append({
        "class": "availability",
        "severity": "critical",
        "status": "FAIL",
        "owner": class_owners["availability"],
        "summary": "Observed endpoints unavailable",
    })
elif availability_status == "WARN":
    signals.append({
        "class": "availability",
        "severity": "warn",
        "status": "WARN",
        "owner": class_owners["availability"],
        "summary": "Observed endpoints warn",
    })

capacity_status = sources["capacity"].get("status")
if capacity_status == "FAIL":
    signals.append({
        "class": "capacity",
        "severity": "critical",
        "status": "FAIL",
        "owner": class_owners["capacity"],
        "summary": "Capacity guard failure (deny)"
    })
elif capacity_status == "WARN":
    signals.append({
        "class": "capacity",
        "severity": "warn",
        "status": "WARN",
        "owner": class_owners["capacity"],
        "summary": "Capacity guard warning"
    })

bindings_status = sources["configuration"].get("status")
if bindings_status == "FAIL":
    signals.append({
        "class": "configuration",
        "severity": "warn",
        "status": "FAIL",
        "owner": class_owners["configuration"],
        "summary": "Binding mismatch between declared and rendered manifests",
    })
elif bindings_status == "WARN":
    signals.append({
        "class": "configuration",
        "severity": "warn",
        "status": "WARN",
        "owner": class_owners["configuration"],
        "summary": "Rendered manifests present without matching bindings",
    })

unknown_sources = [
    key for key, val in sources.items()
    if val.get("status") in {"UNKNOWN", None}
]

if not signals:
    if unknown_sources:
        signals.append({
            "class": "unknown",
            "severity": "warn",
            "status": "UNKNOWN",
            "owner": class_owners["unknown"],
            "summary": "Insufficient observation data",
        })
    else:
        signals.append({
            "class": "none",
            "severity": "info",
            "status": "PASS",
            "owner": class_owners["none"],
            "summary": "No drift detected",
        })

# Determine overall
max_sev = max(signals, key=lambda s: severity_rank.get(s["severity"], 0))
overall = {
    "class": max_sev["class"],
    "severity": max_sev["severity"],
    "status": max_sev["status"],
}

result = {
    "tenant": tenant,
    "timestamp": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "overall": overall,
    "signals": signals,
    "sources": {
        key: val.get("status") for key, val in sources.items()
    },
}

with open(output_path, "w", encoding="utf-8") as fh:
    json.dump(result, fh, sort_keys=True, indent=2)
    fh.write("\n")
PY
