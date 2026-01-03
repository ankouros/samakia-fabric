#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE12_PART3_ENTRY_CHECKLIST.md"
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
# Phase 12 Part 3 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE12_PART1_ACCEPTED.md"
  "acceptance/PHASE12_PART2_ACCEPTED.md"
  "acceptance/PHASE11_HARDENING_ACCEPTED.md"
)

for marker in "${markers[@]}"; do
  cmd="test -f ${marker}"
  if [[ -f "${FABRIC_REPO_ROOT}/${marker}" ]]; then
    pass "Marker present: ${marker}" "${cmd}"
  else
    fail "Marker present: ${marker}" "${cmd}" "missing marker"
  fi
 done

if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
  fail "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md" "OPEN items found"
else
  pass "REQUIRED-FIXES.md has no OPEN items" "rg -n \"OPEN\" REQUIRED-FIXES.md"
fi

files=(
  "ops/bindings/verify/verify.sh"
  "ops/bindings/verify/probes/tcp_tls.sh"
  "ops/bindings/verify/probes/postgres.sh"
  "ops/bindings/verify/probes/mariadb.sh"
  "ops/bindings/verify/probes/rabbitmq.sh"
  "ops/bindings/verify/probes/dragonfly.sh"
  "ops/bindings/verify/probes/qdrant.sh"
  "ops/bindings/verify/common/redact.sh"
  "ops/bindings/verify/common/timeouts.sh"
  "ops/bindings/verify/common/json.sh"
  "ops/policy/policy-bindings-verify.sh"
  "docs/bindings/verification.md"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
 done

if rg -n "VERIFY_LIVE" "${FABRIC_REPO_ROOT}/ops/bindings/verify/verify.sh" >/dev/null 2>&1; then
  pass "Live mode guarded" "rg -n \"VERIFY_LIVE\" ops/bindings/verify/verify.sh"
else
  fail "Live mode guarded" "rg -n \"VERIFY_LIVE\" ops/bindings/verify/verify.sh" "missing guard"
fi

if rg -n "live mode is not allowed in CI" "${FABRIC_REPO_ROOT}/ops/bindings/verify/verify.sh" >/dev/null 2>&1; then
  pass "CI guard for live mode" "rg -n \"live mode is not allowed in CI\" ops/bindings/verify/verify.sh"
else
  fail "CI guard for live mode" "rg -n \"live mode is not allowed in CI\" ops/bindings/verify/verify.sh" "missing guard"
fi

if rg -n "policy-bindings-verify\.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gate wired" "rg -n \"policy-bindings-verify\.sh\" ops/policy/policy.sh"
else
  fail "Policy gate wired" "rg -n \"policy-bindings-verify\.sh\" ops/policy/policy.sh" "policy gate not wired"
fi

make_targets=(
  "bindings.verify.offline"
  "bindings.verify.live"
  "phase12.part3.entry.check"
  "phase12.part3.accept"
)

for target in "${make_targets[@]}"; do
  cmd="rg -n '^${target//./\.}:' Makefile"
  if rg -n "^${target//./\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "${cmd}"
  else
    fail "Makefile target present: ${target}" "${cmd}" "missing target"
  fi
 done

if rg -n "bindings\.verify\.offline" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes bindings verify offline" "rg -n \"bindings\\.verify\\.offline\" docs/operator/cookbook.md"
else
  fail "Cookbook includes bindings verify offline" "rg -n \"bindings\\.verify\\.offline\" docs/operator/cookbook.md" "missing task"
fi

if rg -n "bindings\.verify\.live" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes bindings verify live" "rg -n \"bindings\\.verify\\.live\" docs/operator/cookbook.md"
else
  fail "Cookbook includes bindings verify live" "rg -n \"bindings\\.verify\\.live\" docs/operator/cookbook.md" "missing task"
fi

if rg -n "evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "Evidence paths gitignored" "rg -n \"evidence/\" .gitignore"
else
  fail "Evidence paths gitignored" "rg -n \"evidence/\" .gitignore" "missing gitignore rule"
fi

if rg -n "artifacts/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  pass "Artifacts paths gitignored" "rg -n \"artifacts/\" .gitignore"
else
  fail "Artifacts paths gitignored" "rg -n \"artifacts/\" .gitignore" "missing gitignore rule"
fi
