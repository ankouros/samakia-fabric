#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

out_file="${FABRIC_REPO_ROOT}/acceptance/PHASE16_PART1_ENTRY_CHECKLIST.md"
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
# Phase 16 Part 1 Entry Checklist

Timestamp (UTC): ${stamp}

## Criteria
EOF_HEAD

markers=(
  "acceptance/MILESTONE_PHASE1_12_ACCEPTED.md"
  "acceptance/PHASE13_ACCEPTED.md"
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
  "contracts/ai/provider.schema.json"
  "contracts/ai/provider.yml"
  "contracts/ai/routing.schema.json"
  "contracts/ai/routing.yml"
  "contracts/ai/README.md"
  "docs/ai/overview.md"
  "docs/ai/provider.md"
  "docs/ai/routing.md"
  "docs/operator/ai.md"
  "ops/ai/ai.sh"
  "ops/ai/validate-config.sh"
  "ops/policy/policy-ai-provider.sh"
  "ops/policy/policy-ai-routing.sh"
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

run_check "AI contracts validate" "bash ${FABRIC_REPO_ROOT}/ops/ai/validate-config.sh"

if rg -n "apply|remediate|execute" "${FABRIC_REPO_ROOT}/ops/ai/ai.sh" >/dev/null 2>&1; then
  fail "AI CLI is action-free" "rg -n \"apply|remediate|execute\" ops/ai/ai.sh" "action keywords found"
else
  pass "AI CLI is action-free" "rg -n \"apply|remediate|execute\" ops/ai/ai.sh"
fi

endpoint_cmd="rg -n --glob '!ops/policy/policy-ai-provider.sh' --glob '!ops/scripts/phase16-part1-entry-check.sh' --glob '!acceptance/**' \"api\\.openai\\.com|api\\.anthropic\\.com|generativelanguage\\.googleapis\\.com|aiplatform\\.googleapis\\.com|api\\.cohere\\.ai|api\\.mistral\\.ai|api\\.groq\\.com|openai\\.azure\\.com\" ${FABRIC_REPO_ROOT}"
if rg -n --glob '!ops/policy/policy-ai-provider.sh' --glob '!ops/scripts/phase16-part1-entry-check.sh' --glob '!acceptance/**' \
  "api\.openai\.com|api\.anthropic\.com|generativelanguage\.googleapis\.com|aiplatform\.googleapis\.com|api\.cohere\.ai|api\.mistral\.ai|api\.groq\.com|openai\.azure\.com" \
  "${FABRIC_REPO_ROOT}" >/dev/null 2>&1; then
  fail "No external AI endpoints referenced" "${endpoint_cmd}" "external endpoints found"
else
  pass "No external AI endpoints referenced" "${endpoint_cmd}"
fi

keys_cmd="rg -n --glob '!ops/policy/policy-ai-provider.sh' --glob '!ops/scripts/phase16-part1-entry-check.sh' --glob '!acceptance/**' \"OPENAI_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY|COHERE_API_KEY|MISTRAL_API_KEY|GROQ_API_KEY|AZURE_OPENAI\" ${FABRIC_REPO_ROOT}"
if rg -n --glob '!ops/policy/policy-ai-provider.sh' --glob '!ops/scripts/phase16-part1-entry-check.sh' --glob '!acceptance/**' \
  "OPENAI_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY|COHERE_API_KEY|MISTRAL_API_KEY|GROQ_API_KEY|AZURE_OPENAI" \
  "${FABRIC_REPO_ROOT}" >/dev/null 2>&1; then
  fail "No external AI API keys referenced" "${keys_cmd}" "external API keys found"
else
  pass "No external AI API keys referenced" "${keys_cmd}"
fi

if rg -n "policy-ai-provider\.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gate wired: policy-ai-provider.sh" "rg -n policy-ai-provider\\.sh ops/policy/policy.sh"
else
  fail "Policy gate wired: policy-ai-provider.sh" "rg -n policy-ai-provider\\.sh ops/policy/policy.sh" "policy gate missing"
fi

if rg -n "policy-ai-routing\.sh" "${FABRIC_REPO_ROOT}/ops/policy/policy.sh" >/dev/null 2>&1; then
  pass "Policy gate wired: policy-ai-routing.sh" "rg -n policy-ai-routing\\.sh ops/policy/policy.sh"
else
  fail "Policy gate wired: policy-ai-routing.sh" "rg -n policy-ai-routing\\.sh ops/policy/policy.sh" "policy gate missing"
fi

make_targets=(
  "phase16.part1.entry.check"
  "phase16.part1.accept"
)

for target in "${make_targets[@]}"; do
  if rg -n "^${target//./\\.}:" "${FABRIC_REPO_ROOT}/Makefile" >/dev/null 2>&1; then
    pass "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile"
  else
    fail "Makefile target present: ${target}" "rg -n '^${target//./\\.}:' Makefile" "missing target"
  fi
done

run_check "Policy check" "make -C ${FABRIC_REPO_ROOT} policy.check"
run_check "Operator docs check" "make -C ${FABRIC_REPO_ROOT} docs.operator.check"
