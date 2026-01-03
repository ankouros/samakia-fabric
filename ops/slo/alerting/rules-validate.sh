#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


ALERTS_ROOT="${SLO_ALERTS_ROOT:-${FABRIC_REPO_ROOT}/artifacts/slo-alerts}"

if [[ ! -d "${ALERTS_ROOT}" ]]; then
  echo "ERROR: slo alerts root not found: ${ALERTS_ROOT}" >&2
  exit 2
fi

mapfile -t rule_files < <(find "${ALERTS_ROOT}" -type f -name "rules.yaml" -print 2>/dev/null | sort)

if [[ "${#rule_files[@]}" -eq 0 ]]; then
  echo "ERROR: no SLO alert rules found under ${ALERTS_ROOT}" >&2
  exit 2
fi

for rule_file in "${rule_files[@]}"; do
  if [[ ! -f "${rule_file}" ]]; then
    echo "ERROR: missing rules file: ${rule_file}" >&2
    exit 2
  fi

  python3 - "${rule_file}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = json.loads(path.read_text())
if not isinstance(data, dict):
    raise SystemExit("rules file must be a JSON object")

groups = data.get("groups")
if not isinstance(groups, list) or not groups:
    raise SystemExit("rules file missing groups")

metadata = data.get("metadata", {})
if metadata.get("delivery") != "disabled":
    raise SystemExit("alert delivery must be disabled")

for group in groups:
    rules = group.get("rules") if isinstance(group, dict) else None
    if not isinstance(rules, list) or not rules:
        raise SystemExit("rules group missing rules")
    for rule in rules:
        if not isinstance(rule, dict):
            raise SystemExit("rule must be an object")
        if not rule.get("alert") or not rule.get("expr"):
            raise SystemExit("rule missing alert or expr")
        labels = rule.get("labels", {})
        if not isinstance(labels, dict):
            raise SystemExit("rule labels must be object")
        if labels.get("delivery") != "disabled":
            raise SystemExit("rule delivery must be disabled")
PY

  manifest="$(dirname "${rule_file}")/manifest.sha256"
  if [[ ! -f "${manifest}" ]]; then
    echo "ERROR: missing manifest for rules: ${manifest}" >&2
    exit 2
  fi

  (cd "$(dirname "${rule_file}")" && sha256sum -c "manifest.sha256" >/dev/null)

  echo "PASS: alert rules validated ${rule_file}"

done
