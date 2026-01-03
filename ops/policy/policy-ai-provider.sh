#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: required file missing: ${path}" >&2
    exit 1
  fi
}

provider_file="${FABRIC_REPO_ROOT}/contracts/ai/provider.yml"
provider_schema="${FABRIC_REPO_ROOT}/contracts/ai/provider.schema.json"

require_file "${provider_file}"
require_file "${provider_schema}"

bash "${FABRIC_REPO_ROOT}/ops/ai/validate-config.sh"

PROVIDER_FILE="${provider_file}" python3 - <<'PY'
import os
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for provider check: {exc}")

provider_path = os.environ["PROVIDER_FILE"]
provider = yaml.safe_load(open(provider_path, "r", encoding="utf-8"))

expected = {
    "provider": "ollama",
    "base_url": "http://192.168.11.30:11434",
    "allow_external_providers": False,
    "mode": "analysis-only",
}

errors = []
for key, value in expected.items():
    if provider.get(key) != value:
        errors.append(f"{key} must be {value} (got {provider.get(key)})")

if errors:
    for err in errors:
        print(f"ERROR: {err}")
    sys.exit(1)

print("PASS: AI provider contract enforced")
PY

# Block external provider endpoints and API keys
if rg -n --glob '!ops/policy/policy-ai-provider.sh' --glob '!ops/scripts/phase16-part1-entry-check.sh' \
  --glob '!acceptance/**' \
  "api\.openai\.com|api\.anthropic\.com|generativelanguage\.googleapis\.com|aiplatform\.googleapis\.com|api\.cohere\.ai|api\.mistral\.ai|api\.groq\.com|openai\.azure\.com" \
  "${FABRIC_REPO_ROOT}" >/dev/null 2>&1; then
  echo "ERROR: external AI provider endpoints are not allowed" >&2
  exit 1
fi

if rg -n --glob '!ops/policy/policy-ai-provider.sh' --glob '!ops/scripts/phase16-part1-entry-check.sh' \
  --glob '!acceptance/**' \
  "OPENAI_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY|COHERE_API_KEY|MISTRAL_API_KEY|GROQ_API_KEY|AZURE_OPENAI" \
  "${FABRIC_REPO_ROOT}" >/dev/null 2>&1; then
  echo "ERROR: external AI provider API keys are not allowed" >&2
  exit 1
fi

echo "OK: AI provider policy checks passed"
