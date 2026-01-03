#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE11_PART4_ENTRY_CHECKLIST.md"
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
# Phase 11 Part 4 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

marker="acceptance/PHASE11_PART3_ACCEPTED.md"
cmd="test -f ${marker}"
if [[ -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
  pass "Phase 11 Part 3 accepted" "${cmd}"
else
  fail "Phase 11 Part 3 accepted" "${cmd}" "missing Part 3 marker"
fi

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  fail "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md" "OPEN items found"
else
  pass "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md"
fi

files=(
  "ops/substrate/observe/observe-engine.sh"
  "ops/substrate/observe/compare-engine.sh"
  "ops/substrate/observe/observe.sh"
  "ops/substrate/observe/compare.sh"
  "ops/substrate/observe/normalize-json.sh"
  "ops/substrate/postgres/observe.sh"
  "ops/substrate/postgres/normalize.sh"
  "ops/substrate/postgres/compare.sh"
  "ops/substrate/mariadb/observe.sh"
  "ops/substrate/mariadb/normalize.sh"
  "ops/substrate/mariadb/compare.sh"
  "ops/substrate/rabbitmq/observe.sh"
  "ops/substrate/rabbitmq/normalize.sh"
  "ops/substrate/rabbitmq/compare.sh"
  "ops/substrate/cache/observe.sh"
  "ops/substrate/cache/normalize.sh"
  "ops/substrate/cache/compare.sh"
  "ops/substrate/qdrant/observe.sh"
  "ops/substrate/qdrant/normalize.sh"
  "ops/substrate/qdrant/compare.sh"
  "docs/substrate/observability.md"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "substrate.observe" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: substrate.observe" "rg -n \"substrate.observe\" Makefile"
else
  fail "Makefile target present: substrate.observe" "rg -n \"substrate.observe\" Makefile" "missing target"
fi

if rg -n "substrate.observe.compare" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: substrate.observe.compare" "rg -n \"substrate.observe.compare\" Makefile"
else
  fail "Makefile target present: substrate.observe.compare" "rg -n \"substrate.observe.compare\" Makefile" "missing target"
fi

if rg -n "phase11.part4.entry.check" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.part4.entry.check" "rg -n \"phase11.part4.entry.check\" Makefile"
else
  fail "Makefile target present: phase11.part4.entry.check" "rg -n \"phase11.part4.entry.check\" Makefile" "missing target"
fi

if rg -n "phase11.part4.accept" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase11.part4.accept" "rg -n \"phase11.part4.accept\" Makefile"
else
  fail "Makefile target present: phase11.part4.accept" "rg -n \"phase11.part4.accept\" Makefile" "missing target"
fi

if rg -n "substrate.observe" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1; then
  pass "PR validation includes substrate.observe" "rg -n \"substrate.observe\" .github/workflows/pr-validate.yml"
else
  fail "PR validation includes substrate.observe" "rg -n \"substrate.observe\" .github/workflows/pr-validate.yml" "missing CI gate"
fi

if rg -n "substrate.observe.compare" "${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml" >/dev/null 2>&1; then
  pass "PR validation includes substrate.observe.compare" "rg -n \"substrate.observe.compare\" .github/workflows/pr-validate.yml"
else
  fail "PR validation includes substrate.observe.compare" "rg -n \"substrate.observe.compare\" .github/workflows/pr-validate.yml" "missing CI gate"
fi

if rg -n "evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "Evidence paths gitignored" "rg -n \"evidence/\" .gitignore"
else
  fail "Evidence paths gitignored" "rg -n \"evidence/\" .gitignore" "missing gitignore rule"
fi
