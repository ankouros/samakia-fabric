#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

policy_file="${POLICY_FILE:-${FABRIC_REPO_ROOT}/contracts/observability/policy.yml}"
policy_schema="${SCHEMA_FILE:-${FABRIC_REPO_ROOT}/contracts/observability/policy.schema.json}"

env_name="${ENV:-samakia-shared}"
source_mode="${SOURCE_MODE:-tf-output}"
tf_output="${TF_OUTPUT_PATH:-}"

topology_path=""

usage() {
  cat >&2 <<'EOT'
Usage:
  validate-affinity.sh [--env <name>] [--source tf-output|ansible]
                       [--tf-output <path>] [--topology <path>]
EOT
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      env_name="${2:-}"
      shift 2
      ;;
    --source)
      source_mode="${2:-}"
      shift 2
      ;;
    --tf-output)
      tf_output="${2:-}"
      shift 2
      ;;
    --topology)
      topology_path="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${topology_path}" ]]; then
  topology_path="$(mktemp)"
  trap 'rm -f "${topology_path}" 2>/dev/null || true' EXIT
  if [[ -n "${tf_output}" ]]; then
    bash "${FABRIC_REPO_ROOT}/ops/observability/validate/validate-topology.sh" \
      --env "${env_name}" --source "${source_mode}" --tf-output "${tf_output}" --output "${topology_path}"
  else
    bash "${FABRIC_REPO_ROOT}/ops/observability/validate/validate-topology.sh" \
      --env "${env_name}" --source "${source_mode}" --output "${topology_path}"
  fi
fi

python3 - "${policy_file}" "${policy_schema}" "${topology_path}" <<'PY'
import json
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for policy validation: {exc}")

policy_path = sys.argv[1]
schema_path = sys.argv[2]
topo_path = sys.argv[3]

with open(policy_path, "r", encoding="utf-8") as fh:
    policy = yaml.safe_load(fh) or {}

with open(topo_path, "r", encoding="utf-8") as fh:
    topo = json.load(fh)

shared = policy.get("shared_observability", {})
anti_affinity = shared.get("anti_affinity_required")
min_hosts = shared.get("min_hosts")

nodes = topo.get("nodes") or []
hosts = topo.get("hosts") or []

if not isinstance(min_hosts, int):
    raise SystemExit("ERROR: shared_observability.min_hosts must be defined")

node_list = [h.get("node") for h in hosts if h.get("node")]
unique_nodes = sorted(set(node_list))

if len(unique_nodes) < min_hosts:
    raise SystemExit(
        f"ERROR: shared observability spans {len(unique_nodes)} host(s), below policy minimum {min_hosts} (nodes: {unique_nodes}). "
        "Fix: spread obs nodes across distinct Proxmox hosts in samakia-shared Terraform."
    )

if anti_affinity is True and len(node_list) != len(unique_nodes):
    raise SystemExit(
        f"ERROR: shared observability violates anti-affinity (nodes: {node_list}). "
        "Fix: ensure obs nodes target distinct Proxmox hosts in samakia-shared Terraform."
    )

print("PASS: shared observability anti-affinity and host distribution validated")
PY
