#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: required file missing: ${path}" >&2
    exit 1
  fi
}

require_exec() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: required executable missing: ${path}" >&2
    exit 1
  fi
}

scripts=(
  "${FABRIC_REPO_ROOT}/ops/slo/ingest.sh"
  "${FABRIC_REPO_ROOT}/ops/slo/evaluate.sh"
  "${FABRIC_REPO_ROOT}/ops/slo/windows.sh"
  "${FABRIC_REPO_ROOT}/ops/slo/error-budget.sh"
  "${FABRIC_REPO_ROOT}/ops/slo/normalize.sh"
  "${FABRIC_REPO_ROOT}/ops/slo/redact.sh"
  "${FABRIC_REPO_ROOT}/ops/slo/evidence.sh"
  "${FABRIC_REPO_ROOT}/ops/slo/alerting/rules-generate.sh"
  "${FABRIC_REPO_ROOT}/ops/slo/alerting/rules-validate.sh"
)

for script in "${scripts[@]}"; do
  require_exec "${script}"
  require_file "${script}"
done

if ! rg -n "SLO_LIVE" "${FABRIC_REPO_ROOT}/ops/slo/ingest.sh" >/dev/null 2>&1; then
  echo "ERROR: slo ingest live-mode guard missing" >&2
  exit 1
fi

if ! rg -n "CI" "${FABRIC_REPO_ROOT}/ops/slo/ingest.sh" >/dev/null 2>&1; then
  echo "ERROR: slo ingest CI guard missing" >&2
  exit 1
fi

if ! rg -n "OBSERVATION_PATH" "${FABRIC_REPO_ROOT}/ops/slo/ingest.sh" >/dev/null 2>&1; then
  echo "ERROR: slo ingest must use observation contract" >&2
  exit 1
fi

if ! rg -n "OBSERVATION_PATH" "${FABRIC_REPO_ROOT}/ops/slo/normalize.sh" >/dev/null 2>&1; then
  echo "ERROR: slo normalization must use observation contract" >&2
  exit 1
fi

if ! rg -n "delivery\": \"disabled\"" "${FABRIC_REPO_ROOT}/ops/slo/alerting/rules-generate.sh" >/dev/null 2>&1; then
  echo "ERROR: slo alert rules must default delivery to disabled" >&2
  exit 1
fi

if rg -n "alertmanager|pagerduty|opsgenie|slack|webhook|remediate|self-heal" "${FABRIC_REPO_ROOT}/ops/slo" >/dev/null 2>&1; then
  echo "ERROR: slo tooling must not enable delivery or remediation" >&2
  exit 1
fi

if rg -n "(curl|wget|ssh|terraform|ansible-playbook)" "${FABRIC_REPO_ROOT}/ops/slo" >/dev/null 2>&1; then
  echo "ERROR: slo tooling must remain read-only (unexpected network or exec tool found)" >&2
  exit 1
fi

if ! rg -n "^evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  echo "ERROR: evidence/ not gitignored" >&2
  exit 1
fi

if ! rg -n "^artifacts/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  echo "ERROR: artifacts/ not gitignored" >&2
  exit 1
fi

echo "policy-slo: OK"
