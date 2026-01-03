#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE16_PART2_ENTRY_CHECKLIST.md"
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
# Phase 16 Part 2 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE16_PART1_ACCEPTED.md"
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
  "contracts/ai/qdrant.schema.json"
  "contracts/ai/qdrant.yml"
  "contracts/ai/indexing.schema.json"
  "contracts/ai/indexing.yml"
  "docs/ai/qdrant.md"
  "docs/ai/indexing.md"
  "docs/operator/ai.md"
  "ops/ai/indexer/indexer.sh"
  "ops/ai/indexer/lib/chunk.sh"
  "ops/ai/indexer/lib/hash.sh"
  "ops/ai/indexer/lib/redact.sh"
  "ops/ai/indexer/lib/qdrant.sh"
  "ops/ai/indexer/lib/ollama.sh"
  "ops/ai/indexer/lib/manifest.sh"
  "ops/ai/indexer/lib/json.sh"
  "ops/ai/indexer/sources/docs.sh"
  "ops/ai/indexer/sources/contracts.sh"
  "ops/ai/indexer/sources/runbooks.sh"
  "ops/ai/indexer/sources/evidence.sh"
  "ops/ai/indexer/fixtures/sample-docs/overview.md"
  "ops/ai/indexer/fixtures/sample-contracts/sample.yml"
  "ops/ai/indexer/fixtures/sample-evidence/report.md"
  "ops/ai/indexer/fixtures/sample-runbooks/runbook.md"
  "ops/policy/policy-ai-qdrant.sh"
  "ops/policy/policy-ai-indexing.sh"
  "OPERATIONS.md"
  "ROADMAP.md"
  "CHANGELOG.md"
  "REVIEW.md"
)

for file in "${files[@]}"; do
  cmd="test -f ${file}"
  if [[ -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    pass "File present: ${file}" "${cmd}"
  else
    fail "File present: ${file}" "${cmd}" "missing file"
  fi
done

if rg -n "policy-ai-qdrant\.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gate wired: policy-ai-qdrant.sh" "rg -n policy-ai-qdrant\\.sh ops/policy/policy.sh"
else
  fail "Policy gate wired: policy-ai-qdrant.sh" "rg -n policy-ai-qdrant\\.sh ops/policy/policy.sh" "policy gate missing"
fi

if rg -n "policy-ai-indexing\.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gate wired: policy-ai-indexing.sh" "rg -n policy-ai-indexing\\.sh ops/policy/policy.sh"
else
  fail "Policy gate wired: policy-ai-indexing.sh" "rg -n policy-ai-indexing\\.sh ops/policy/policy.sh" "policy gate missing"
fi

make_targets=(
  "ai.index.doctor"
  "ai.index.preview"
  "ai.index.offline"
  "ai.index.live"
  "phase16.part2.entry.check"
  "phase16.part2.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile" "missing target"
  fi
done

run_check "Evidence paths gitignored" "rg -n '^evidence/' ${FABRIC_REPO_ROOT}/.gitignore"
run_check "CI wiring: ai.index.offline" "rg -n 'ai\.index\.offline' ${FABRIC_REPO_ROOT}/.github/workflows/pr-validate.yml"
run_check "AI indexing doctor" "make -C ${FABRIC_REPO_ROOT} ai.index.doctor"
run_check "Policy check" "make -C ${FABRIC_REPO_ROOT} policy.check"
run_check "Operator docs check" "make -C ${FABRIC_REPO_ROOT} docs.operator.check"
