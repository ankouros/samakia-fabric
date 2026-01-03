#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE14_PART3_ENTRY_CHECKLIST.md"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

pass() {
  local label="$1"
  local cmd="$2"
  {
    echo "- ${label}"
    echo "  - Command: ${cmd}"
    echo "  - Result: PASS"
  } >>"${out_file}"
}

fail() {
  local label="$1"
  local cmd="$2"
  local reason="$3"
  {
    echo "- ${label}"
    echo "  - Command: ${cmd}"
    echo "  - Result: FAIL"
    echo "  - Reason: ${reason}"
  } >>"${out_file}"
  exit 1
}

run_check() {
  local label="$1"
  local cmd="$2"
  if bash -lc "${cmd}"; then
    pass "${label}" "${cmd}"
  else
    fail "${label}" "${cmd}" "command failed"
  fi
}

cat >"${out_file}" <<EOF_HEAD
# Phase 14 Part 3 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE14_PART2_ACCEPTED.md"
  "acceptance/PHASE14_PART1_ACCEPTED.md"
  "acceptance/PHASE13_ACCEPTED.md"
  "acceptance/MILESTONE_PHASE1_12_ACCEPTED.md"
)

for marker in "${markers[@]}"; do
  cmd="test -f ${marker}"
  if [[ -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
    pass "Acceptance marker present: ${marker}" "${cmd}"
  else
    fail "Acceptance marker present: ${marker}" "${cmd}" "missing marker"
  fi
done

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  fail "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md" "OPEN items found"
else
  pass "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md"
fi

files=(
  "ops/alerts/deliver.sh"
  "ops/alerts/validate.sh"
  "ops/alerts/route.sh"
  "ops/alerts/redact.sh"
  "ops/alerts/evidence.sh"
  "ops/alerts/format/slack.sh"
  "ops/alerts/format/webhook.sh"
  "ops/alerts/format/email.sh"
  "ops/incidents/open.sh"
  "ops/incidents/update.sh"
  "ops/incidents/close.sh"
  "ops/incidents/validate.sh"
  "contracts/incidents/incident.schema.json"
  "contracts/alerting/routing.yml"
  "docs/operator/alerts.md"
  "docs/operator/incidents.md"
  "docs/runtime/incident-lifecycle.md"
  "ops/policy/policy-alerts.sh"
  "ops/policy/policy-incidents.sh"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "policy-alerts.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gates wired: policy-alerts.sh" "rg -n policy-alerts.sh ops/policy/policy.sh"
else
  fail "Policy gates wired: policy-alerts.sh" "rg -n policy-alerts.sh ops/policy/policy.sh" "policy gate missing"
fi

if rg -n "policy-incidents.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gates wired: policy-incidents.sh" "rg -n policy-incidents.sh ops/policy/policy.sh"
else
  fail "Policy gates wired: policy-incidents.sh" "rg -n policy-incidents.sh ops/policy/policy.sh" "policy gate missing"
fi

make_targets=(
  "alerts.validate"
  "alerts.deliver"
  "incidents.open"
  "incidents.update"
  "incidents.close"
  "phase14.part3.entry.check"
  "phase14.part3.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile" "missing target"
  fi
done

run_check "CI wiring: alerts.validate" "rg -n 'alerts.validate' .github/workflows/pr-validate.yml"
run_check "No automation hooks" "! rg -n 'remediate|self-heal|auto-remediate|autoscale|auto-scale' ops/alerts ops/incidents"

run_check "Policy check" "make -C ${FABRIC_REPO_ROOT} policy.check"
run_check "Runtime evaluate" "make -C ${FABRIC_REPO_ROOT} runtime.evaluate TENANT=all"
run_check "SLO evaluate" "make -C ${FABRIC_REPO_ROOT} slo.evaluate TENANT=all"
