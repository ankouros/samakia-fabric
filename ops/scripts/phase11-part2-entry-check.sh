#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE11_PART2_ENTRY_CHECKLIST.md"
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
# Phase 11 Part 2 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

marker="acceptance/PHASE11_PART1_ACCEPTED.md"
cmd="test -f ${marker}"
if [[ -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
  pass "Phase 11 Part 1 accepted" "${cmd}"
else
  fail "Phase 11 Part 1 accepted" "${cmd}" "missing Part 1 marker"
fi

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  fail "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md" "OPEN items found"
else
  pass "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md"
fi

scripts=(
  "ops/substrate/common/execute-policy.yml"
  "ops/substrate/common/validate-execute-policy.sh"
  "ops/substrate/common/enforce-execute-policy.sh"
  "ops/substrate/common/dr-run.sh"
  "ops/substrate/postgres/apply.sh"
  "ops/substrate/postgres/verify.sh"
  "ops/substrate/mariadb/apply.sh"
  "ops/substrate/mariadb/verify.sh"
  "ops/substrate/rabbitmq/apply.sh"
  "ops/substrate/rabbitmq/verify.sh"
  "ops/substrate/cache/apply.sh"
  "ops/substrate/cache/verify.sh"
  "ops/substrate/qdrant/apply.sh"
  "ops/substrate/qdrant/verify.sh"
  "ops/substrate/postgres/backup.sh"
  "ops/substrate/postgres/restore.sh"
  "ops/substrate/mariadb/backup.sh"
  "ops/substrate/mariadb/restore.sh"
  "ops/substrate/rabbitmq/backup.sh"
  "ops/substrate/rabbitmq/restore.sh"
  "ops/substrate/cache/backup.sh"
  "ops/substrate/cache/restore.sh"
  "ops/substrate/qdrant/backup.sh"
  "ops/substrate/qdrant/restore.sh"
)

for script in "${scripts[@]}"; do
  cmd="test -f ${script}"
  if [[ -f "${FABRIC_REPO_ROOT}/${script}" ]]; then
    pass "Script present: ${script}" "${cmd}"
  else
    fail "Script present: ${script}" "${cmd}" "missing script"
  fi
done

if rg -n "^substrate\.apply:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: substrate.apply" "rg -n '^substrate\\.apply:' Makefile"
else
  fail "Makefile target present: substrate.apply" "rg -n '^substrate\\.apply:' Makefile" "missing target"
fi

if rg -n "^substrate\.verify:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: substrate.verify" "rg -n '^substrate\\.verify:' Makefile"
else
  fail "Makefile target present: substrate.verify" "rg -n '^substrate\\.verify:' Makefile" "missing target"
fi

if rg -n "^substrate\.dr\.execute:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: substrate.dr.execute" "rg -n '^substrate\\.dr\\.execute:' Makefile"
else
  fail "Makefile target present: substrate.dr.execute" "rg -n '^substrate\\.dr\\.execute:' Makefile" "missing target"
fi

if rg -n "^phase11\.part2\.entry\.check:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.part2.entry.check" "rg -n '^phase11\\.part2\\.entry\\.check:' Makefile"
else
  fail "Makefile target present: phase11.part2.entry.check" "rg -n '^phase11\\.part2\\.entry\\.check:' Makefile" "missing target"
fi

if rg -n "^phase11\.part2\.accept:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.part2.accept" "rg -n '^phase11\\.part2\\.accept:' Makefile"
else
  fail "Makefile target present: phase11.part2.accept" "rg -n '^phase11\\.part2\\.accept:' Makefile" "missing target"
fi

if rg -n "substrate\.apply" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes substrate apply task" "rg -n \"substrate\\.apply\" docs/operator/cookbook.md"
else
  fail "Cookbook includes substrate apply task" "rg -n \"substrate\\.apply\" docs/operator/cookbook.md" "missing cookbook task"
fi

if rg -n "substrate\.dr\.execute" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes substrate DR execute task" "rg -n \"substrate\\.dr\\.execute\" docs/operator/cookbook.md"
else
  fail "Cookbook includes substrate DR execute task" "rg -n \"substrate\\.dr\\.execute\" docs/operator/cookbook.md" "missing cookbook task"
fi

if rg -n "evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "Evidence paths gitignored" "rg -n \"evidence/\" .gitignore"
else
  fail "Evidence paths gitignored" "rg -n \"evidence/\" .gitignore" "missing gitignore rule"
fi
