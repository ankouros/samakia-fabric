#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE17_STEP6_ENTRY_CHECKLIST.md"
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
# Phase 17 Step 6 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE16_PART1_ACCEPTED.md"
  "acceptance/PHASE16_PART2_ACCEPTED.md"
  "acceptance/MILESTONE_PHASE1_12_ACCEPTED.md"
  "acceptance/PHASE17_STEP5_ACCEPTED.md"
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
  "ops/ai/indexer/indexer.sh"
  "ops/ai/indexer/lib/ollama.sh"
  "ops/ai/indexer/lib/qdrant.sh"
  "ops/ai/indexer/lib/redact.sh"
  "ops/ai/indexer/lib/chunk.sh"
  "ops/ai/qdrant/doctor.sh"
  "ops/ai/n8n/README.md"
  "ops/ai/n8n/validate-workflows.sh"
  "ops/ai/n8n/workflows/ingest-evidence.json"
  "ops/ai/n8n/workflows/ingest-contracts.json"
  "ops/ai/n8n/workflows/ingest-runbooks.json"
  "ops/ai/n8n/workflows/ingest-release-readiness.json"
  "ops/policy/policy-ai-live-indexing.sh"
  "ops/policy/policy-ai-n8n.sh"
  "docs/ai/indexing.md"
  "docs/operator/ai.md"
  "docs/operator/cookbook.md"
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

if rg -n "policy-ai-live-indexing.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Live indexing policy wired" "rg -n policy-ai-live-indexing.sh ops/policy/policy.sh"
else
  fail "Live indexing policy wired" "rg -n policy-ai-live-indexing.sh ops/policy/policy.sh" "missing policy wiring"
fi

if rg -n "policy-ai-n8n.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "n8n policy wired" "rg -n policy-ai-n8n.sh ops/policy/policy.sh"
else
  fail "n8n policy wired" "rg -n policy-ai-n8n.sh ops/policy/policy.sh" "missing policy wiring"
fi

make_targets=(
  "ai.index.offline"
  "ai.index.live"
  "ai.qdrant.doctor"
  "ai.qdrant.doctor.live"
  "ai.n8n.validate"
  "phase17.step6.entry.check"
  "phase17.step6.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile" "missing target"
  fi
done

run_check "Policy gates" "make -C ${FABRIC_REPO_ROOT} policy.check"
run_check "Operator docs check" "make -C ${FABRIC_REPO_ROOT} docs.operator.check"
run_check "Offline fixtures (docs source)" "rg -n 'fixtures/sample-docs' ${FABRIC_REPO_ROOT}/ops/ai/indexer/sources/docs.sh"
run_check "Offline fixtures (contracts source)" "rg -n 'fixtures/sample-contracts' ${FABRIC_REPO_ROOT}/ops/ai/indexer/sources/contracts.sh"
run_check "Offline fixtures (runbooks source)" "rg -n 'fixtures/sample-runbooks' ${FABRIC_REPO_ROOT}/ops/ai/indexer/sources/runbooks.sh"
run_check "Offline fixtures (evidence source)" "rg -n 'fixtures/sample-evidence' ${FABRIC_REPO_ROOT}/ops/ai/indexer/sources/evidence.sh"
