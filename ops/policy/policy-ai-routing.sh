#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: required file missing: ${path}" >&2
    exit 1
  fi
}

routing_file="${FABRIC_REPO_ROOT}/contracts/ai/routing.yml"
routing_schema="${FABRIC_REPO_ROOT}/contracts/ai/routing.schema.json"
ai_cli="${FABRIC_REPO_ROOT}/ops/ai/ai.sh"

require_file "${routing_file}"
require_file "${routing_schema}"
require_file "${ai_cli}"

ROUTING_FILE="${routing_file}" python3 - <<'PY'
import os
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for routing check: {exc}")

routing_path = os.environ["ROUTING_FILE"]
routing = yaml.safe_load(open(routing_path, "r", encoding="utf-8"))

defs = routing.get("defaults", {})
expected_defaults = {
    "ops": "gpt-oss:20b",
    "code": "starcoder2:15b",
    "embeddings": "nomic-embed-text",
}

errors = []
for key, value in expected_defaults.items():
    if defs.get(key) != value:
        errors.append(f"defaults.{key} must be {value} (got {defs.get(key)})")

expected_routes = {
    "ops.analysis": "gpt-oss:20b",
    "ops.summary": "gpt-oss:20b",
    "ops.incident": "gpt-oss:20b",
    "code.review": "starcoder2:15b",
    "code.generate": "starcoder2:15b",
    "embeddings": "nomic-embed-text",
}

routes = {route.get("task"): route.get("model") for route in routing.get("routes", [])}

if set(routes.keys()) != set(expected_routes.keys()):
    errors.append("routing tasks must match the allowlist")

for task, model in expected_routes.items():
    if routes.get(task) != model:
        errors.append(f"route {task} must use {model} (got {routes.get(task)})")

if errors:
    for err in errors:
        print(f"ERROR: {err}")
    sys.exit(1)

print("PASS: AI routing policy enforced")
PY

if rg -n "curl|wget" "${ai_cli}" >/dev/null 2>&1; then
  echo "ERROR: AI CLI must be offline (no network calls)" >&2
  exit 1
fi

if rg -n "apply|remediate|execute" "${ai_cli}" >/dev/null 2>&1; then
  echo "ERROR: AI CLI must remain read-only" >&2
  exit 1
fi

echo "OK: AI routing policy checks passed"
