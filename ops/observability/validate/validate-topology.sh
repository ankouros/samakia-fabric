#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

env_name="${ENV:-samakia-shared}"
source_mode="tf-output"
tf_output=""
output_path=""

usage() {
  cat >&2 <<'EOT'
Usage:
  validate-topology.sh [--env <name>] [--source tf-output|ansible]
                       [--tf-output <path>] [--output <path>]

Defaults:
  --env samakia-shared
  --source tf-output
  --tf-output uses TF_OUTPUT_PATH or fabric-core/terraform/envs/<env>/terraform-output.json
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
    --output)
      output_path="${2:-}"
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

if [[ -z "${env_name}" ]]; then
  echo "ERROR: --env is required" >&2
  exit 2
fi

if [[ "${source_mode}" != "tf-output" && "${source_mode}" != "ansible" ]]; then
  echo "ERROR: --source must be tf-output or ansible (got: ${source_mode})" >&2
  exit 2
fi

if [[ "${source_mode}" == "ansible" ]]; then
  if ! command -v ansible-inventory >/dev/null 2>&1; then
    echo "ERROR: ansible-inventory is required for --source ansible" >&2
    exit 1
  fi
fi

if [[ -z "${tf_output}" ]]; then
  tf_output="${TF_OUTPUT_PATH:-${FABRIC_REPO_ROOT}/fabric-core/terraform/envs/${env_name}/terraform-output.json}"
fi

python3 - "${env_name}" "${source_mode}" "${tf_output}" "${output_path}" <<'PY'
import json
import os
import subprocess
import sys

env_name = sys.argv[1]
source_mode = sys.argv[2]
tf_output = sys.argv[3]
output_path = sys.argv[4]

hosts = []

if source_mode == "tf-output":
    if not os.path.exists(tf_output):
        raise SystemExit(f"ERROR: terraform output not found: {tf_output}")
    with open(tf_output, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    lxc_inventory = data.get("lxc_inventory", {}).get("value", {}) or {}
    for entry in lxc_inventory.values():
        hostname = entry.get("hostname")
        if hostname and hostname.startswith("obs-"):
            hosts.append({
                "hostname": hostname,
                "node": entry.get("node"),
                "vmid": entry.get("vmid"),
            })
else:
    inventory_script = os.path.join(os.environ["FABRIC_REPO_ROOT"], "fabric-core", "ansible", "inventory", "terraform.py")
    env = os.environ.copy()
    env["FABRIC_TERRAFORM_ENV"] = env_name
    result = subprocess.run(
        ["ansible-inventory", "-i", inventory_script, "--list"],
        capture_output=True,
        text=True,
        env=env,
    )
    if result.returncode != 0:
        raise SystemExit(f"ERROR: ansible-inventory failed: {result.stderr.strip()}")
    inventory = json.loads(result.stdout)
    hostvars = inventory.get("_meta", {}).get("hostvars", {}) or {}
    for hostname, vars in hostvars.items():
        if hostname.startswith("obs-"):
            hosts.append({
                "hostname": hostname,
                "node": vars.get("proxmox_node") or vars.get("node"),
                "vmid": vars.get("vmid"),
            })

if not hosts:
    raise SystemExit("ERROR: no observability hosts found (expected hostnames starting with 'obs-')")

missing_node = [h["hostname"] for h in hosts if not h.get("node")]
if missing_node:
    raise SystemExit(f"ERROR: observability hosts missing node assignment: {', '.join(sorted(missing_node))}")

nodes = sorted({h["node"] for h in hosts})

payload = {
    "env": env_name,
    "hosts": hosts,
    "replicas": len(hosts),
    "nodes": nodes,
}

encoded = json.dumps(payload, indent=2, sort_keys=True)
if output_path:
    with open(output_path, "w", encoding="utf-8") as fh:
        fh.write(encoded + "\n")
else:
    print(encoded)
PY
