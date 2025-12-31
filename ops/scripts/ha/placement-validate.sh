#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

POLICY_FILE="${FABRIC_REPO_ROOT}/fabric-core/ha/placement-policy.yml"
INVENTORY_SCRIPT="${FABRIC_REPO_ROOT}/fabric-core/ansible/inventory/terraform.py"

usage() {
  cat >&2 <<'EOT'
Usage:
  placement-validate.sh [--env <env>] [--all]

Validates placement policy against Terraform inventory (read-only).
Defaults to --all (validate all envs defined in policy).
EOT
}

if [[ ! -f "${POLICY_FILE}" ]]; then
  echo "ERROR: placement policy not found: ${POLICY_FILE}" >&2
  exit 1
fi

if ! command -v ansible-inventory >/dev/null 2>&1; then
  echo "ERROR: ansible-inventory is required for placement validation." >&2
  exit 1
fi

mode="all"
explicit_env=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      explicit_env="${2:-}"
      mode="env"
      shift 2
      ;;
    --all)
      mode="all"
      shift
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

if [[ "${mode}" == "env" && -z "${explicit_env}" ]]; then
  echo "ERROR: --env requires a value" >&2
  exit 2
fi

python3 - "${POLICY_FILE}" "${INVENTORY_SCRIPT}" "${mode}" "${explicit_env}" <<'PY'
import json
import os
import subprocess
import sys
from typing import Dict, List

policy_path = sys.argv[1]
inventory_script = sys.argv[2]
mode = sys.argv[3]
explicit_env = sys.argv[4]

with open(policy_path, "r", encoding="utf-8") as fh:
    policy = json.load(fh)

envs = policy.get("envs", {})
if not isinstance(envs, dict) or not envs:
    print("ERROR: placement policy has no envs defined", file=sys.stderr)
    sys.exit(1)

if mode == "env":
    env_list = [explicit_env]
else:
    env_list = sorted(envs.keys())

nodes_allowed = set(policy.get("failure_domains", {}).get("nodes", []))
if not nodes_allowed:
    print("ERROR: placement policy has no failure domain nodes defined", file=sys.stderr)
    sys.exit(1)

errors: List[str] = []

for env_name in env_list:
    env_policy = envs.get(env_name)
    if env_policy is None:
        errors.append(f"{env_name}: not found in placement policy")
        continue

    workloads = env_policy.get("workloads", [])
    if not workloads:
        errors.append(f"{env_name}: no workloads defined in placement policy")
        continue

    env_vars = os.environ.copy()
    env_vars["FABRIC_TERRAFORM_ENV"] = env_name
    result = subprocess.run(
        ["ansible-inventory", "-i", inventory_script, "--list"],
        capture_output=True,
        text=True,
        env=env_vars,
    )
    if result.returncode != 0:
        errors.append(f"{env_name}: ansible-inventory failed: {result.stderr.strip()}")
        continue

    try:
        inventory = json.loads(result.stdout)
    except Exception as exc:
        errors.append(f"{env_name}: failed to parse inventory JSON: {exc}")
        continue

    hostvars: Dict[str, Dict] = inventory.get("_meta", {}).get("hostvars", {}) or {}
    hosts = inventory.get("all", {}).get("hosts", []) or list(hostvars.keys())

    policy_hosts = []
    for workload in workloads:
        policy_hosts.extend(workload.get("hosts", []) or [])

    policy_hosts_set = set(policy_hosts)
    inventory_hosts_set = set(hosts)

    missing_hosts = sorted(policy_hosts_set - inventory_hosts_set)
    if missing_hosts:
        errors.append(f"{env_name}: hosts missing from inventory: {', '.join(missing_hosts)}")

    extra_hosts = sorted(inventory_hosts_set - policy_hosts_set)
    if extra_hosts:
        errors.append(f"{env_name}: hosts not classified in placement policy: {', '.join(extra_hosts)}")

    for workload in workloads:
        name = workload.get("name")
        w_hosts = workload.get("hosts", []) or []
        if not w_hosts:
            errors.append(f"{env_name}: workload '{name}' has no hosts defined")
            continue

        replicas = workload.get("replicas")
        if isinstance(replicas, int) and replicas != len(w_hosts):
            errors.append(
                f"{env_name}: workload '{name}' replicas mismatch (replicas={replicas}, hosts={len(w_hosts)})"
            )

        nodes = []
        for host in w_hosts:
            node = hostvars.get(host, {}).get("proxmox_node")
            if not node:
                errors.append(f"{env_name}: host '{host}' missing proxmox_node in inventory")
                continue
            if node not in nodes_allowed:
                errors.append(
                    f"{env_name}: host '{host}' on unknown node '{node}' (allowed: {sorted(nodes_allowed)})"
                )
            nodes.append(node)

        if workload.get("anti_affinity"):
            if len(nodes) != len(set(nodes)):
                remaining = sorted(nodes_allowed - set(nodes))
                errors.append(
                    f"{env_name}: workload '{name}' violates anti-affinity (nodes={nodes}); available nodes: {remaining}"
                )

if errors:
    for line in errors:
        print(f"FAIL: {line}", file=sys.stderr)
    sys.exit(1)

print("PASS: placement policy validated against inventory")
PY
