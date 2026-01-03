#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ROUTING_FILE="${FABRIC_REPO_ROOT}/contracts/ai/routing.yml" python3 - <<'PY'
import os

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for routing test: {exc}")

routing_file = os.environ["ROUTING_FILE"]
routing = yaml.safe_load(open(routing_file, "r", encoding="utf-8"))

expected_defaults = {
    "ops": "gpt-oss:20b",
    "code": "starcoder2:15b",
    "embeddings": "nomic-embed-text",
}

defaults = routing.get("defaults", {})
for key, value in expected_defaults.items():
    if defaults.get(key) != value:
        raise SystemExit(f"ERROR: routing default {key} mismatch")

expected_routes = {
    "ops.analysis": "gpt-oss:20b",
    "ops.summary": "gpt-oss:20b",
    "ops.incident": "gpt-oss:20b",
    "code.review": "starcoder2:15b",
    "code.generate": "starcoder2:15b",
    "embeddings": "nomic-embed-text",
}

routes = {route.get("task"): route.get("model") for route in routing.get("routes", [])}
for task, model in expected_routes.items():
    if routes.get(task) != model:
        raise SystemExit(f"ERROR: routing task {task} mismatch")

print("PASS: routing policy locked")
PY
