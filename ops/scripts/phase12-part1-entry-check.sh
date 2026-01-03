#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE12_PART1_ENTRY_CHECKLIST.md"
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
# Phase 12 Part 1 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

marker="acceptance/PHASE11_HARDENING_ACCEPTED.md"
cmd="test -f ${marker}"
if [[ -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
  pass "Phase 11 hardening accepted" "${cmd}"
else
  fail "Phase 11 hardening accepted" "${cmd}" "missing hardening marker"
fi

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  fail "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md" "OPEN items found"
else
  pass "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md"
fi

files=(
  "contracts/bindings/_schema/binding.schema.json"
  "contracts/bindings/_templates/binding.yml"
  "docs/bindings/README.md"
  "docs/bindings/secrets.md"
  "ops/bindings/validate/validate-binding-schema.sh"
  "ops/bindings/validate/validate-binding-semantics.sh"
  "ops/bindings/validate/validate-binding-safety.sh"
  "ops/bindings/render/render-connection-manifest.sh"
  "ops/bindings/apply/bind.sh"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "bindings\.validate" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes bindings tasks" "rg -n \"bindings\\.validate\" docs/operator/cookbook.md"
else
  fail "Cookbook includes bindings tasks" "rg -n \"bindings\\.validate\" docs/operator/cookbook.md" "missing binding tasks"
fi

if rg -n "^bindings\.validate:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: bindings.validate" "rg -n '^bindings\\.validate:' Makefile"
else
  fail "Makefile target present: bindings.validate" "rg -n '^bindings\\.validate:' Makefile" "missing target"
fi

if rg -n "^bindings\.render:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: bindings.render" "rg -n '^bindings\\.render:' Makefile"
else
  fail "Makefile target present: bindings.render" "rg -n '^bindings\\.render:' Makefile" "missing target"
fi

if rg -n "^bindings\.apply:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: bindings.apply" "rg -n '^bindings\\.apply:' Makefile"
else
  fail "Makefile target present: bindings.apply" "rg -n '^bindings\\.apply:' Makefile" "missing target"
fi

if rg -n "^phase12\.part1\.entry\.check:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase12.part1.entry.check" "rg -n '^phase12\\.part1\\.entry\\.check:' Makefile"
else
  fail "Makefile target present: phase12.part1.entry.check" "rg -n '^phase12\\.part1\\.entry\\.check:' Makefile" "missing target"
fi

if rg -n "^phase12\.part1\.accept:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
  pass "Makefile target present: phase12.part1.accept" "rg -n '^phase12\\.part1\\.accept:' Makefile"
else
  fail "Makefile target present: phase12.part1.accept" "rg -n '^phase12\\.part1\\.accept:' Makefile" "missing target"
fi

if rg -n "artifacts/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "Artifacts paths gitignored" "rg -n \"artifacts/\" .gitignore"
else
  fail "Artifacts paths gitignored" "rg -n \"artifacts/\" .gitignore" "missing gitignore rule"
fi

if rg -n "evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "Evidence paths gitignored" "rg -n \"evidence/\" .gitignore"
else
  fail "Evidence paths gitignored" "rg -n \"evidence/\" .gitignore" "missing gitignore rule"
fi
