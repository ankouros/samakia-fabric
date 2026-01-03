#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

require_exec() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: required executable missing: ${path}" >&2
    exit 1
  fi
}

scripts=(
  "${FABRIC_REPO_ROOT}/ops/alerts/deliver.sh"
  "${FABRIC_REPO_ROOT}/ops/alerts/validate.sh"
  "${FABRIC_REPO_ROOT}/ops/alerts/route.sh"
  "${FABRIC_REPO_ROOT}/ops/alerts/redact.sh"
  "${FABRIC_REPO_ROOT}/ops/alerts/evidence.sh"
  "${FABRIC_REPO_ROOT}/ops/alerts/format/slack.sh"
  "${FABRIC_REPO_ROOT}/ops/alerts/format/webhook.sh"
  "${FABRIC_REPO_ROOT}/ops/alerts/format/email.sh"
)

for script in "${scripts[@]}"; do
  require_exec "${script}"
done

if ! rg -n "ALERTS_ENABLE" "${FABRIC_REPO_ROOT}/ops/alerts/deliver.sh" >/dev/null 2>&1; then
  echo "ERROR: alerts deliver must gate on ALERTS_ENABLE" >&2
  exit 1
fi

if ! rg -n "ALERT_SINK" "${FABRIC_REPO_ROOT}/ops/alerts/deliver.sh" >/dev/null 2>&1; then
  echo "ERROR: alerts deliver must require ALERT_SINK" >&2
  exit 1
fi

if ! rg -n "CI" "${FABRIC_REPO_ROOT}/ops/alerts/deliver.sh" >/dev/null 2>&1; then
  echo "ERROR: alerts deliver must guard CI delivery" >&2
  exit 1
fi

if ! rg -n "slack|webhook|email" "${FABRIC_REPO_ROOT}/ops/alerts/deliver.sh" >/dev/null 2>&1; then
  echo "ERROR: alerts deliver must allowlist sinks" >&2
  exit 1
fi

if rg -n "(curl|wget|ssh|terraform|ansible-playbook|remediate|self-heal)" "${FABRIC_REPO_ROOT}/ops/alerts" >/dev/null 2>&1; then
  echo "ERROR: alerts tooling must remain read-only" >&2
  exit 1
fi

if ! rg -n "^evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  echo "ERROR: evidence/ not gitignored" >&2
  exit 1
fi

echo "policy-alerts: OK"
