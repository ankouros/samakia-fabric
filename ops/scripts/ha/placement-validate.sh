#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


POLICY_FILE="${FABRIC_REPO_ROOT}/fabric-core/ha/placement-policy.yml"
INVENTORY_SCRIPT="${FABRIC_REPO_ROOT}/fabric-core/ansible/inventory/terraform.py"
TF_ENVS_DIR="${FABRIC_REPO_ROOT}/fabric-core/terraform/envs"

usage() {
  cat >&2 <<'EOT'
Usage:
  placement-validate.sh [--env <env>] [--all] [--enforce]
                        [--policy <path>] [--inventory-source ansible|tf-output]
                        [--inventory-json <path>]

Validates placement policy against inventory (read-only).
Defaults to --all (validate all envs defined in policy).

Notes:
- --inventory-source=tf-output reads terraform output for each env and does not
  require ansible-inventory or Proxmox API access.
- --inventory-json accepts an ansible-style inventory JSON file (fixtures/tests).
  This is intended for synthetic enforcement tests.
EOT
}

mode="all"
explicit_env=""
enforce_mode="0"
inventory_source="ansible"
inventory_json=""
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
    --enforce)
      enforce_mode="1"
      shift
      ;;
    --policy)
      POLICY_FILE="${2:-}"
      shift 2
      ;;
    --inventory-source)
      inventory_source="${2:-}"
      shift 2
      ;;
    --inventory-json)
      inventory_json="${2:-}"
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

if [[ "${mode}" == "env" && -z "${explicit_env}" ]]; then
  echo "ERROR: --env requires a value" >&2
  exit 2
fi

if [[ ! -f "${POLICY_FILE}" ]]; then
  echo "ERROR: placement policy not found: ${POLICY_FILE}" >&2
  exit 1
fi

if [[ "${inventory_source}" != "ansible" && "${inventory_source}" != "tf-output" ]]; then
  echo "ERROR: --inventory-source must be ansible or tf-output (got: ${inventory_source})" >&2
  exit 2
fi

if [[ -n "${inventory_json}" && ! -f "${inventory_json}" ]]; then
  echo "ERROR: inventory JSON not found: ${inventory_json}" >&2
  exit 1
fi

if [[ -n "${inventory_json}" && "${mode}" != "env" ]]; then
  echo "ERROR: --inventory-json requires --env (single environment only)" >&2
  exit 2
fi

if [[ "${inventory_source}" == "ansible" ]]; then
  if ! command -v ansible-inventory >/dev/null 2>&1; then
    echo "ERROR: ansible-inventory is required for placement validation." >&2
    exit 1
  fi
fi

python3 - "${POLICY_FILE}" "${INVENTORY_SCRIPT}" "${TF_ENVS_DIR}" "${mode}" "${explicit_env}" "${inventory_source}" "${inventory_json}" "${enforce_mode}" <<'PY'
import json
import os
import subprocess
import sys
from typing import Dict, List

policy_path = sys.argv[1]
inventory_script = sys.argv[2]
tf_envs_dir = sys.argv[3]
mode = sys.argv[4]
explicit_env = sys.argv[5]
inventory_source = sys.argv[6]
inventory_json = sys.argv[7]
enforce_mode = sys.argv[8] == "1"

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
warnings: List[str] = []

def load_inventory_ansible(env_name: str) -> tuple[Dict[str, Dict], List[str], str | None]:
    env_vars = os.environ.copy()
    env_vars["FABRIC_TERRAFORM_ENV"] = env_name
    result = subprocess.run(
        ["ansible-inventory", "-i", inventory_script, "--list"],
        capture_output=True,
        text=True,
        env=env_vars,
    )
    if result.returncode != 0:
        return {}, [], result.stderr.strip()
    try:
        inventory = json.loads(result.stdout)
    except Exception as exc:
        return {}, [], f"failed to parse inventory JSON: {exc}"
    hostvars = inventory.get("_meta", {}).get("hostvars", {}) or {}
    hosts = inventory.get("all", {}).get("hosts", []) or list(hostvars.keys())
    return hostvars, hosts, None

def load_inventory_tf_output(env_name: str) -> tuple[Dict[str, Dict], List[str], str | None]:
    env_dir = os.path.join(tf_envs_dir, env_name)
    tf_output_path = os.path.join(env_dir, "terraform-output.json")
    data = None
    try:
        result = subprocess.run(
            ["terraform", f"-chdir={env_dir}", "output", "-json"],
            capture_output=True,
            text=True,
            env={**os.environ, "TF_INPUT": "0"},
        )
        if result.returncode == 0 and result.stdout.strip():
            data = json.loads(result.stdout)
    except Exception:
        data = None

    if data is None and os.path.exists(tf_output_path):
        try:
            with open(tf_output_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception as exc:
            return {}, [], f"failed to parse terraform-output.json: {exc}"

    if data is None:
        return {}, [], "terraform output unavailable (run terraform apply or set TF_OUTPUT_PATH)"

    lxc_inventory = data.get("lxc_inventory", {}).get("value", {}) or {}
    hostvars: Dict[str, Dict] = {}
    hosts: List[str] = []
    for entry in lxc_inventory.values():
        hostname = entry.get("hostname")
        node = entry.get("node")
        vmid = entry.get("vmid")
        if not hostname or not node:
            continue
        hosts.append(hostname)
        hostvars[hostname] = {"proxmox_node": node, "vmid": vmid}
    if not hosts:
        return {}, [], "terraform output has no lxc_inventory entries"
    return hostvars, hosts, None

def load_inventory_from_json(path: str) -> tuple[Dict[str, Dict], List[str], str | None]:
    try:
        payload = json.load(open(path, "r", encoding="utf-8"))
    except Exception as exc:
        return {}, [], f"failed to parse inventory JSON: {exc}"
    if "_meta" in payload:
        hostvars = payload.get("_meta", {}).get("hostvars", {}) or {}
        hosts = payload.get("all", {}).get("hosts", []) or list(hostvars.keys())
    else:
        hostvars = payload.get("hostvars", {}) or {}
        hosts = payload.get("hosts", []) or list(hostvars.keys())
    return hostvars, hosts, None

def load_inventory(env_name: str) -> tuple[Dict[str, Dict], List[str], str | None]:
    if inventory_json:
        return load_inventory_from_json(inventory_json)
    if inventory_source == "tf-output":
        return load_inventory_tf_output(env_name)
    return load_inventory_ansible(env_name)

tiers = policy.get("tiers", {}) or {}

def add_error(msg: str) -> None:
    errors.append(msg)

def add_warning(msg: str) -> None:
    warnings.append(msg)

for env_name in env_list:
    env_policy = envs.get(env_name)
    if env_policy is None:
        add_error(f"{env_name}: not found in placement policy")
        continue

    workloads = env_policy.get("workloads", [])
    if not workloads:
        add_error(f"{env_name}: no workloads defined in placement policy")
        continue

    hostvars, hosts, load_err = load_inventory(env_name)
    if load_err:
        add_error(f"{env_name}: inventory load failed: {load_err}")
        continue

    policy_hosts = []
    for workload in workloads:
        policy_hosts.extend(workload.get("hosts", []) or [])

    policy_hosts_set = set(policy_hosts)
    inventory_hosts_set = set(hosts)

    missing_hosts = sorted(policy_hosts_set - inventory_hosts_set)
    if missing_hosts:
        add_error(f"{env_name}: hosts missing from inventory: {', '.join(missing_hosts)}")

    extra_hosts = sorted(inventory_hosts_set - policy_hosts_set)
    if extra_hosts:
        add_error(f"{env_name}: hosts not classified in placement policy: {', '.join(extra_hosts)}")

    for workload in workloads:
        name = workload.get("name")
        w_hosts = workload.get("hosts", []) or []
        tier = workload.get("tier")
        if not w_hosts:
            add_error(f"{env_name}: workload '{name}' has no hosts defined")
            continue
        if tier not in tiers:
            add_error(f"{env_name}: workload '{name}' has unknown tier '{tier}'")

        replicas = workload.get("replicas")
        if isinstance(replicas, int) and replicas != len(w_hosts):
            msg = f"{env_name}: workload '{name}' replicas mismatch (replicas={replicas}, hosts={len(w_hosts)})"
            if enforce_mode and tier == "tier2":
                add_warning(msg)
            else:
                add_error(msg)

        nodes = []
        for host in w_hosts:
            node = hostvars.get(host, {}).get("proxmox_node")
            if not node:
                add_error(f"{env_name}: host '{host}' missing proxmox_node in inventory")
                continue
            if node not in nodes_allowed:
                add_error(
                    f"{env_name}: host '{host}' on unknown node '{node}' (allowed: {sorted(nodes_allowed)})"
                )
            nodes.append(node)

        anti_affinity = bool(workload.get("anti_affinity"))
        if anti_affinity and len(nodes) != len(set(nodes)):
            remaining = sorted(nodes_allowed - set(nodes))
            msg = (
                f"{env_name}: workload '{name}' violates anti-affinity (nodes={nodes}); "
                f"available nodes: {remaining}"
            )
            if enforce_mode and tier == "tier2":
                add_warning(msg)
            else:
                add_error(msg)

        if enforce_mode and tier in ("tier0", "tier1"):
            if not anti_affinity:
                add_error(f"{env_name}: workload '{name}' tier={tier} requires anti_affinity=true")
            if isinstance(replicas, int) and replicas < 2:
                add_error(f"{env_name}: workload '{name}' tier={tier} requires replicas>=2")
            if len(w_hosts) < 2:
                add_error(f"{env_name}: workload '{name}' tier={tier} requires at least 2 hosts")
            if len(nodes) != len(set(nodes)):
                remaining = sorted(nodes_allowed - set(nodes))
                add_error(
                    f"{env_name}: workload '{name}' tier={tier} requires distinct nodes; "
                    f"nodes={nodes}; available nodes: {remaining}"
                )

if warnings:
    for line in warnings:
        print(f"WARN: {line}")

if errors and enforce_mode:
    override = os.environ.get("HA_OVERRIDE") == "1"
    reason = (os.environ.get("HA_OVERRIDE_REASON") or "").strip()
    if override and reason:
        print("FAIL-OVERRIDDEN: placement enforcement violations present")
        print(f"OVERRIDE_REASON: {reason}")
        for line in errors:
            print(f"OVERRIDE: {line}")
        sys.exit(0)
    if override and not reason:
        print("FAIL: HA_OVERRIDE=1 set but HA_OVERRIDE_REASON is missing", file=sys.stderr)
        sys.exit(1)
    for line in errors:
        print(f"FAIL: {line}", file=sys.stderr)
    sys.exit(1)

if errors:
    for line in errors:
        print(f"FAIL: {line}", file=sys.stderr)
    sys.exit(1)

print("PASS: placement policy validated against inventory")
PY
