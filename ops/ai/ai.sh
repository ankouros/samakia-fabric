#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  ai.sh doctor
  ai.sh route <task>

Commands:
  doctor        Validate config and print a summary (no network)
  route <task>  Print which model would be used for the task
EOT
}

cmd="${1:-}"
case "${cmd}" in
  doctor)
    bash "${FABRIC_REPO_ROOT}/ops/ai/validate-config.sh"
    PROVIDER_FILE="${FABRIC_REPO_ROOT}/contracts/ai/provider.yml" \
    ROUTING_FILE="${FABRIC_REPO_ROOT}/contracts/ai/routing.yml" python3 - <<'PY'
import os
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for summary: {exc}")

provider_path = os.environ["PROVIDER_FILE"]
routing_path = os.environ["ROUTING_FILE"]

provider = yaml.safe_load(open(provider_path, "r", encoding="utf-8"))
routing = yaml.safe_load(open(routing_path, "r", encoding="utf-8"))

def line(label, value):
    print(f"{label}: {value}")

print("AI configuration summary")
line("provider", provider.get("provider"))
line("base_url", provider.get("base_url"))
line("mode", provider.get("mode"))
line("allow_external_providers", provider.get("allow_external_providers"))

defs = routing.get("defaults", {})
line("defaults.ops", defs.get("ops"))
line("defaults.code", defs.get("code"))
line("defaults.embeddings", defs.get("embeddings"))

print("routes:")
for route in routing.get("routes", []):
    task = route.get("task")
    model = route.get("model")
    print(f"- {task} -> {model}")
PY
    ;;
  route)
    task="${2:-}"
    if [[ -z "${task}" ]]; then
      usage
      exit 2
    fi
    ROUTING_FILE="${FABRIC_REPO_ROOT}/contracts/ai/routing.yml" TASK="${task}" python3 - <<'PY'
import os
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for routing: {exc}")

routing_path = os.environ["ROUTING_FILE"]
request_task = os.environ["TASK"]

routing = yaml.safe_load(open(routing_path, "r", encoding="utf-8"))

defs = routing.get("defaults", {})
routes = routing.get("routes", [])

model = None
source = "default"

for route in routes:
    if route.get("task") == request_task:
        model = route.get("model")
        source = "explicit"
        break

if model is None:
    if request_task.startswith("ops."):
        model = defs.get("ops")
    elif request_task.startswith("code."):
        model = defs.get("code")
    elif request_task == "embeddings" or request_task.startswith("embeddings."):
        model = defs.get("embeddings")

if not model:
    raise SystemExit(f"ERROR: no routing match for task '{request_task}'")

print(f"task: {request_task}")
print(f"model: {model}")
print(f"source: {source}")
PY
    ;;
  -h|--help|help|"")
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac
