#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


POLICY_FILE="${FABRIC_REPO_ROOT}/fabric-core/ha/placement-policy.yml"
TF_ENVS_DIR="${FABRIC_REPO_ROOT}/fabric-core/terraform/envs"

usage() {
  cat >&2 <<'EOT'
Usage:
  proxmox-ha-audit.sh [--enforce] [--env <env>] [--all] [--policy <path>]

Read-only audit of Proxmox HA resources. Fails if HA resources
exist while policy expects none, or if policy expects HA but none exist.
EOT
}

mode="audit"
mode_env="all"
explicit_env=""
policy_path="${POLICY_FILE}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --enforce)
      mode="enforce"
      shift
      ;;
    --env)
      explicit_env="${2:-}"
      mode_env="env"
      shift 2
      ;;
    --all)
      mode_env="all"
      shift
      ;;
    --policy)
      policy_path="${2:-}"
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

if [[ "${mode_env}" == "env" && -z "${explicit_env}" ]]; then
  echo "ERROR: --env requires a value" >&2
  exit 2
fi

if [[ ! -f "${policy_path}" ]]; then
  echo "ERROR: placement policy not found: ${policy_path}" >&2
  exit 1
fi

api_url="${TF_VAR_pm_api_url:-${PM_API_URL:-}}"
token_id="${TF_VAR_pm_api_token_id:-${PM_API_TOKEN_ID:-}}"
token_secret="${TF_VAR_pm_api_token_secret:-${PM_API_TOKEN_SECRET:-}}"

if [[ -z "${api_url}" || -z "${token_id}" || -z "${token_secret}" ]]; then
  echo "ERROR: missing Proxmox API env vars (TF_VAR_pm_api_url/TF_VAR_pm_api_token_id/TF_VAR_pm_api_token_secret)." >&2
  exit 1
fi

if [[ "${token_id}" != *"!"* ]]; then
  echo "ERROR: Proxmox token id must include '!': ${token_id}" >&2
  exit 1
fi

header="Authorization: PVEAPIToken=${token_id}=${token_secret}"
url="${api_url%/}/cluster/ha/resources"

tmp_payload="$(mktemp)"
http_code="$(curl -sS -o "${tmp_payload}" -w "%{http_code}" -H "${header}" "${url}" || true)"
if [[ "${http_code}" != "200" ]]; then
  echo "ERROR: Proxmox HA resources query failed (http_code=${http_code}): ${url}" >&2
  if [[ -s "${tmp_payload}" ]]; then
    head -n 5 "${tmp_payload}" >&2 || true
  fi
  rm -f "${tmp_payload}"
  exit 1
fi

if [[ ! -s "${tmp_payload}" ]]; then
  echo "ERROR: Proxmox HA resources query returned empty JSON payload: ${url}" >&2
  rm -f "${tmp_payload}"
  exit 1
fi

python3 - "${policy_path}" "${TF_ENVS_DIR}" "${tmp_payload}" "${mode}" "${mode_env}" "${explicit_env}" <<'PY'
import json
import sys
from pathlib import Path

policy_path = sys.argv[1]
tf_envs_dir = Path(sys.argv[2])
payload_path = sys.argv[3]
mode = sys.argv[4]
mode_env = sys.argv[5]
explicit_env = sys.argv[6]
try:
    policy = json.load(open(policy_path, "r", encoding="utf-8"))
except Exception as exc:
    print(f"FAIL: could not parse placement policy: {exc}", file=sys.stderr)
    sys.exit(1)

envs = policy.get("envs", {}) or {}
if mode_env == "env":
    if explicit_env not in envs:
        print(f"FAIL: env '{explicit_env}' not found in placement policy", file=sys.stderr)
        sys.exit(1)
    env_list = [explicit_env]
else:
    env_list = sorted(envs.keys())

try:
    payload = json.load(open(payload_path, "r", encoding="utf-8"))
except Exception as exc:
    print(f"FAIL: could not parse Proxmox HA response: {exc}", file=sys.stderr)
    sys.exit(1)
resources = payload.get("data", []) or []

def parse_resource_vmid(res: dict) -> str | None:
    rid = res.get("sid") or res.get("id") or res.get("resource") or ""
    if isinstance(rid, str) and ":" in rid:
        return rid.split(":")[-1]
    if isinstance(rid, str) and rid.isdigit():
        return rid
    return None

ha_vmids = set()
if resources:
    print("INFO: Proxmox HA resources detected:")
    for res in resources:
        rid = res.get("sid") or res.get("id") or res.get("resource") or "unknown"
        group = res.get("group") or "(none)"
        state = res.get("state") or res.get("status") or "unknown"
        print(f"- {rid} group={group} state={state}")
        vmid = parse_resource_vmid(res)
        if vmid:
            ha_vmids.add(vmid)

expected_vmids_global: set[str] = set()
expected_vmids_scope: set[str] = set()

def load_tf_output(env_name: str) -> dict:
    env_dir = tf_envs_dir / env_name
    tf_output = env_dir / "terraform-output.json"
    if not tf_output.exists():
        return {}
    try:
        return json.load(open(tf_output, "r", encoding="utf-8"))
    except Exception:
        return {}

for env_name, env in envs.items():
    if not isinstance(env, dict):
        continue
    workloads = env.get("workloads", []) or []
    proxmox_hosts = []
    for workload in workloads:
        if workload.get("ha_mode") == "proxmox":
            proxmox_hosts.extend(workload.get("hosts", []) or [])
    if not proxmox_hosts:
        continue
    data = load_tf_output(env_name)
    lxc_inventory = data.get("lxc_inventory", {}).get("value", {}) or {}
    host_to_vmid = {}
    for entry in lxc_inventory.values():
        hostname = entry.get("hostname")
        vmid = entry.get("vmid")
        if hostname and vmid:
            host_to_vmid[hostname] = str(vmid)
    missing = [h for h in proxmox_hosts if h not in host_to_vmid]
    if missing:
        print(f"FAIL: env {env_name} proxmox HA hosts missing in terraform output: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)
    vmids = {host_to_vmid[h] for h in proxmox_hosts}
    expected_vmids_global.update(vmids)
    if env_name in env_list:
        expected_vmids_scope.update(vmids)

unexpected = ha_vmids - expected_vmids_global
missing = expected_vmids_scope - ha_vmids

violations = []
if expected_vmids_global:
    if unexpected:
        violations.append(f"unexpected Proxmox HA resources present: {sorted(unexpected)}")
    if missing:
        violations.append(f"expected Proxmox HA resources missing: {sorted(missing)}")
else:
    if ha_vmids:
        violations.append("Proxmox HA resources exist, but placement policy declares none")

if violations:
    override = os.environ.get("HA_OVERRIDE") == "1"
    reason = (os.environ.get("HA_OVERRIDE_REASON") or "").strip()
    if mode == "enforce" and override and reason:
        print("FAIL-OVERRIDDEN: Proxmox HA enforcement violations present")
        print(f"OVERRIDE_REASON: {reason}")
        for line in violations:
            print(f"OVERRIDE: {line}")
        sys.exit(0)
    if mode == "enforce" and override and not reason:
        print("FAIL: HA_OVERRIDE=1 set but HA_OVERRIDE_REASON is missing", file=sys.stderr)
        sys.exit(1)
    for line in violations:
        print(f"FAIL: {line}", file=sys.stderr)
    sys.exit(1)

print("PASS: Proxmox HA audit matches placement policy")
PY
rm -f "${tmp_payload}"
