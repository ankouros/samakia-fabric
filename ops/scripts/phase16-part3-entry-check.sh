#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE16_PART3_ENTRY_CHECKLIST.md"
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
# Phase 16 Part 3 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/PHASE16_PART2_ACCEPTED.md"
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
  "ops/ai/mcp/common/server.py"
  "ops/ai/mcp/common/auth.sh"
  "ops/ai/mcp/common/allowlist.sh"
  "ops/ai/mcp/common/redact.sh"
  "ops/ai/mcp/common/audit.sh"
  "ops/ai/mcp/common/errors.sh"
  "ops/ai/mcp/repo/server.sh"
  "ops/ai/mcp/repo/handlers.sh"
  "ops/ai/mcp/repo/allowlist.yml"
  "ops/ai/mcp/evidence/server.sh"
  "ops/ai/mcp/evidence/handlers.sh"
  "ops/ai/mcp/evidence/allowlist.yml"
  "ops/ai/mcp/observability/server.sh"
  "ops/ai/mcp/observability/handlers.sh"
  "ops/ai/mcp/observability/allowlist.yml"
  "ops/ai/mcp/observability/fixtures/prometheus.json"
  "ops/ai/mcp/observability/fixtures/loki.json"
  "ops/ai/mcp/runbooks/server.sh"
  "ops/ai/mcp/runbooks/handlers.sh"
  "ops/ai/mcp/runbooks/allowlist.yml"
  "ops/ai/mcp/qdrant/server.sh"
  "ops/ai/mcp/qdrant/handlers.sh"
  "ops/ai/mcp/qdrant/allowlist.yml"
  "ops/ai/mcp/qdrant/fixtures/search.json"
  "ops/policy/policy-ai-mcp.sh"
  "docs/ai/mcp.md"
  "docs/operator/ai.md"
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

if rg -n "policy-ai-mcp\.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gate wired: policy-ai-mcp.sh" "rg -n policy-ai-mcp\\.sh ops/policy/policy.sh"
else
  fail "Policy gate wired: policy-ai-mcp.sh" "rg -n policy-ai-mcp\\.sh ops/policy/policy.sh" "policy gate missing"
fi

if rg -n "mcp-audit" "${FABRIC_REPO_ROOT}/ops/ai/mcp/common/server.py" >/dev/null 2>&1; then
  pass "Audit logging implemented" "rg -n mcp-audit ops/ai/mcp/common/server.py"
else
  fail "Audit logging implemented" "rg -n mcp-audit ops/ai/mcp/common/server.py" "audit logging missing"
fi

make_targets=(
  "ai.mcp.doctor"
  "ai.mcp.repo.start"
  "ai.mcp.evidence.start"
  "ai.mcp.observability.start"
  "ai.mcp.runbooks.start"
  "ai.mcp.qdrant.start"
  "phase16.part3.entry.check"
  "phase16.part3.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile" "missing target"
  fi
done

run_check "AI MCP doctor" "make -C ${FABRIC_REPO_ROOT} ai.mcp.doctor"
run_check "MCP policy check" "bash ${FABRIC_REPO_ROOT}/ops/policy/policy-ai-mcp.sh"
run_check "Operator docs check" "make -C ${FABRIC_REPO_ROOT} docs.operator.check"
