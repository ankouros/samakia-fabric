#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE12_PART2_ENTRY_CHECKLIST.md"
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
# Phase 12 Part 2 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE12_PART1_ACCEPTED.md"
  "acceptance/PHASE11_HARDENING_ACCEPTED.md"
  "acceptance/PHASE11_PART4_ACCEPTED.md"
  "acceptance/PHASE10_PART2_ACCEPTED.md"
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
  "contracts/secrets/shapes/postgres.yml"
  "contracts/secrets/shapes/mariadb.yml"
  "contracts/secrets/shapes/rabbitmq.yml"
  "contracts/secrets/shapes/dragonfly.yml"
  "contracts/secrets/shapes/qdrant.yml"
  "docs/bindings/secrets.md"
  "ops/bindings/secrets/backends/file.sh"
  "ops/bindings/secrets/backends/vault.sh"
  "ops/bindings/secrets/materialize.sh"
  "ops/bindings/secrets/inspect.sh"
  "ops/bindings/secrets/generate.sh"
  "ops/bindings/secrets/redact.sh"
  "ops/bindings/rotate/rotate.sh"
  "ops/bindings/rotate/rotate-plan.sh"
  "ops/bindings/rotate/rotate-dryrun.sh"
  "ops/bindings/rotate/rotate-evidence.sh"
  "ops/policy/policy-secrets-materialization.sh"
  "ops/policy/policy-secrets-rotation.sh"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "bindings\.secrets\.materialize" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes secret materialize task" "rg -n \"bindings\\.secrets\\.materialize\" docs/operator/cookbook.md"
else
  fail "Cookbook includes secret materialize task" "rg -n \"bindings\\.secrets\\.materialize\" docs/operator/cookbook.md" "missing task"
fi

if rg -n "bindings\.secrets\.rotate\.plan" "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" >/dev/null 2>&1; then
  pass "Cookbook includes rotation plan task" "rg -n \"bindings\\.secrets\\.rotate\\.plan\" docs/operator/cookbook.md"
else
  fail "Cookbook includes rotation plan task" "rg -n \"bindings\\.secrets\\.rotate\\.plan\" docs/operator/cookbook.md" "missing task"
fi

make_targets=(
  "bindings.secrets.inspect"
  "bindings.secrets.materialize"
  "bindings.secrets.materialize.dryrun"
  "bindings.secrets.rotate.plan"
  "bindings.secrets.rotate.dryrun"
  "bindings.secrets.rotate"
  "phase12.part2.entry.check"
  "phase12.part2.accept"
)

for target in "${make_targets[@]}"; do
  cmd="rg -n '^${target//./\\.}:' Makefile"
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "${cmd}"
  else
    fail "Makefile target present: ${target}" "${cmd}" "missing target"
  fi
done

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
