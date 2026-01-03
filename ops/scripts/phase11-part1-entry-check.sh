#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE11_PART1_ENTRY_CHECKLIST.md"
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

cat >"${out_file}" <<EOF_HEAD
# Phase 11 Part 1 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

marker="acceptance/PHASE11_ACCEPTED.md"
cmd="test -f ${marker}"
if [[ -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
  pass "Phase 11 design accepted" "${cmd}"
else
  fail "Phase 11 design accepted" "${cmd}" "missing design marker"
fi

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  fail "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md" "OPEN items found"
else
  pass "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md"
fi

scripts=(
  "ops/substrate/substrate.sh"
  "ops/substrate/common/env.sh"
  "ops/substrate/common/guards.sh"
  "ops/substrate/common/plan-format.sh"
  "ops/substrate/common/connectivity.sh"
  "ops/substrate/common/redaction.sh"
  "ops/substrate/common/evidence.sh"
  "ops/substrate/postgres/plan.sh"
  "ops/substrate/postgres/dr-dryrun.sh"
  "ops/substrate/mariadb/plan.sh"
  "ops/substrate/mariadb/dr-dryrun.sh"
  "ops/substrate/rabbitmq/plan.sh"
  "ops/substrate/rabbitmq/dr-dryrun.sh"
  "ops/substrate/cache/plan.sh"
  "ops/substrate/cache/dr-dryrun.sh"
  "ops/substrate/qdrant/plan.sh"
  "ops/substrate/qdrant/dr-dryrun.sh"
)

for script in "${scripts[@]}"; do
  cmd="test -f ${script}"
  if [[ -f "${FABRIC_REPO_ROOT}/${script}" ]]; then
    pass "Script present: ${script}" "${cmd}"
  else
    fail "Script present: ${script}" "${cmd}" "missing script"
  fi
done

if rg -n "^substrate\.plan:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: substrate.plan" "rg -n '^substrate\\.plan:' Makefile"
else
  fail "Makefile target present: substrate.plan" "rg -n '^substrate\\.plan:' Makefile" "missing target"
fi

if rg -n "^substrate\.dr\.dryrun:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: substrate.dr.dryrun" "rg -n '^substrate\\.dr\\.dryrun:' Makefile"
else
  fail "Makefile target present: substrate.dr.dryrun" "rg -n '^substrate\\.dr\\.dryrun:' Makefile" "missing target"
fi

if rg -n "^substrate\.plan\.ci:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: substrate.plan.ci" "rg -n '^substrate\\.plan\\.ci:' Makefile"
else
  fail "Makefile target present: substrate.plan.ci" "rg -n '^substrate\\.plan\\.ci:' Makefile" "missing target"
fi

if rg -n "^phase11\.part1\.entry\.check:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.part1.entry.check" "rg -n '^phase11\\.part1\\.entry\\.check:' Makefile"
else
  fail "Makefile target present: phase11.part1.entry.check" "rg -n '^phase11\\.part1\\.entry\\.check:' Makefile" "missing target"
fi

if rg -n "^phase11\.part1\.accept:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.part1.accept" "rg -n '^phase11\\.part1\\.accept:' Makefile"
else
  fail "Makefile target present: phase11.part1.accept" "rg -n '^phase11\\.part1\\.accept:' Makefile" "missing target"
fi

if rg -n "substrate\.plan" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes substrate plan task" "rg -n \"substrate\\.plan\" docs/operator/cookbook.md"
else
  fail "Cookbook includes substrate plan task" "rg -n \"substrate\\.plan\" docs/operator/cookbook.md" "missing cookbook task"
fi

if rg -n "evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "Evidence paths gitignored" "rg -n \"evidence/\" .gitignore"
else
  fail "Evidence paths gitignored" "rg -n \"evidence/\" .gitignore" "missing gitignore rule"
fi
