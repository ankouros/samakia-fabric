#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANSIBLE_DIR="${REPO_ROOT}/fabric-core/ansible"
TF_ENVS_DIR="${REPO_ROOT}/fabric-core/terraform/envs"

usage() {
  cat >&2 <<'EOF'
Usage:
  inventory-sanity-check.sh <env>

Sanity checks DHCP/IP determinism against the inventory contract:
  - If host_vars/<host>.yml pins ansible_host, verify it matches Proxmox API IPv4.
    If mismatch -> FAIL loud with remediation steps.
  - If ansible_host is not pinned, warn (do not fail) when an IP is discovered.
  - If ansible_host is not pinned and Proxmox API cannot discover IP -> FAIL loud
    (inventory will not be resolvable).

Requires (names only; values are not printed):
  TF_VAR_pm_api_url
  TF_VAR_pm_api_token_id
  TF_VAR_pm_api_token_secret

This script never prints token secrets.
EOF
}

ENV_NAME="${1:-}"
if [[ -z "${ENV_NAME}" || "${ENV_NAME}" == "-h" || "${ENV_NAME}" == "--help" ]]; then
  usage
  exit 2
fi

TF_ENV_DIR="${TF_ENVS_DIR}/${ENV_NAME}"
if [[ ! -d "${TF_ENV_DIR}" ]]; then
  echo "ERROR: Terraform env directory not found: ${TF_ENV_DIR}" >&2
  exit 1
fi

if [[ -z "${TF_VAR_pm_api_url:-}" || -z "${TF_VAR_pm_api_token_id:-}" || -z "${TF_VAR_pm_api_token_secret:-}" ]]; then
  echo "ERROR: missing Proxmox API env vars for IP discovery (set TF_VAR_pm_api_url + TF_VAR_pm_api_token_id + TF_VAR_pm_api_token_secret)." >&2
  exit 1
fi

# Guardrails: strict TLS and internal CA on runner host.
bash "${REPO_ROOT}/fabric-ci/scripts/check-proxmox-ca-and-tls.sh"

lxc_json=""
set +e
lxc_json="$(terraform -chdir="${TF_ENV_DIR}" output -json 2>/dev/null)"
rc=$?
set -e

if [[ "${rc}" -ne 0 ]]; then
  tf_output_fallback="${TF_ENV_DIR}/terraform-output.json"
  if [[ -f "${tf_output_fallback}" ]]; then
    lxc_json="$(cat "${tf_output_fallback}")"
  else
    echo "WARN: terraform output not available; skipping inventory sanity check for ${ENV_NAME}." >&2
    exit 0
  fi
fi

tmp_json="$(mktemp)"
trap 'rm -f "${tmp_json}" 2>/dev/null || true' EXIT
printf '%s' "${lxc_json}" >"${tmp_json}"

python3 - "${REPO_ROOT}" "${ANSIBLE_DIR}" "${TF_ENV_DIR}" "${tmp_json}" <<'PY'
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

repo_root = Path(sys.argv[1])
ansible_dir = Path(sys.argv[2])
tf_env_dir = Path(sys.argv[3])
payload_path = Path(sys.argv[4])

payload = json.loads(payload_path.read_text(encoding="utf-8"))
lxc_inventory = payload.get("lxc_inventory", {}).get("value", {})
if not lxc_inventory:
  print(f"WARN: lxc_inventory is empty for {tf_env_dir.name}; nothing to check.", file=sys.stderr)
  sys.exit(0)

host_vars_dir = ansible_dir / "host_vars"

pm_api_url = os.environ.get("TF_VAR_pm_api_url", "").rstrip("/")
token_id = os.environ.get("TF_VAR_pm_api_token_id", "")
token_secret = os.environ.get("TF_VAR_pm_api_token_secret", "")

def load_host_vars(hostname: str) -> dict:
  path = host_vars_dir / f"{hostname}.yml"
  if not path.exists():
    return {}
  out: dict[str, str] = {}
  for raw in path.read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or ":" not in line:
      continue
    k, v = line.split(":", 1)
    k = k.strip()
    v = v.strip().strip("'").strip('"')
    if k:
      out[k] = v
  return out

def fetch_json_retry(url: str, headers: dict[str, str], attempts: int = 8, delay: float = 1.0) -> dict | None:
  last: Exception | None = None
  for _ in range(attempts):
    try:
      req = urllib.request.Request(url, headers=headers)
      with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, ValueError) as exc:
      last = exc
      time.sleep(delay)
  return None

def looks_like_ipv4(value: str) -> bool:
  parts = value.split(".")
  if len(parts) != 4:
    return False
  try:
    nums = [int(p) for p in parts]
  except ValueError:
    return False
  if any(n < 0 or n > 255 for n in nums):
    return False
  return value != "127.0.0.1"

def discover_ipv4(node: str, vmid: int) -> str | None:
  headers = {"Authorization": f"PVEAPIToken={token_id}={token_secret}"}

  url = f"{pm_api_url}/nodes/{node}/lxc/{vmid}/interfaces"
  data = fetch_json_retry(url, headers=headers)
  if data:
    for iface in (data.get("data") or []):
      name = str(iface.get("name") or "")
      if not (name == "eth0" or name.startswith("eth0")):
        continue
      for addr in (iface.get("ip-addresses") or []):
        if addr.get("ip-address-type") not in ("inet", "ipv4"):
          continue
        ip = addr.get("ip-address")
        if ip and looks_like_ipv4(ip):
          return ip

  url = f"{pm_api_url}/nodes/{node}/lxc/{vmid}/status/current"
  data = fetch_json_retry(url, headers=headers)
  if not data:
    return None

  cur = data.get("data")
  if isinstance(cur, dict):
    ip = cur.get("ip")
    if isinstance(ip, str) and looks_like_ipv4(ip):
      return ip
    for v in cur.values():
      if isinstance(v, str) and looks_like_ipv4(v):
        return v
  return None

errors: list[str] = []
warnings: list[str] = []

for _, host in lxc_inventory.items():
  hostname = host["hostname"]
  node = host["node"]
  vmid = int(host["vmid"])

  hv = load_host_vars(hostname)
  pinned = hv.get("ansible_host")

  ip = discover_ipv4(node=node, vmid=vmid)
  if pinned:
    if not ip:
      errors.append(f"{hostname}: host_vars pins ansible_host={pinned} but Proxmox API could not resolve IPv4 (node={node} vmid={vmid}).")
      continue
    if pinned != ip:
      errors.append(
        f"{hostname}: host_vars pins ansible_host={pinned} but Proxmox reports {ip} (node={node} vmid={vmid})."
      )
  else:
    if ip:
      warnings.append(f"{hostname}: ansible_host not pinned; Proxmox reports IPv4={ip} (node={node} vmid={vmid}).")
    else:
      errors.append(
        f"{hostname}: ansible_host not pinned and Proxmox API could not resolve IPv4 (node={node} vmid={vmid}). Ensure DHCP reservation exists for the pinned MAC."
      )

for w in warnings:
  print(f"WARN: {w}", file=sys.stderr)

if errors:
  for e in errors:
    print(f"ERROR: {e}", file=sys.stderr)
  print(
    "\nRemediation:\n"
    "- Ensure DHCP reservations exist for the Terraform-pinned MAC addresses.\n"
    "- If you pin ansible_host in host_vars, update it after any replace/recreate that changes DHCP/IP.\n"
    "- Prefer leaving ansible_host unpinned and relying on Proxmox API discovery unless you need fixed IPs.\n",
    file=sys.stderr,
  )
  sys.exit(1)

print("OK: inventory sanity check passed")
PY
