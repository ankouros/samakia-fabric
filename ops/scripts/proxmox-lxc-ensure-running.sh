#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOF'
Usage:
  proxmox-lxc-ensure-running.sh <env>

Ensures all LXCs declared in terraform-output.json for the given env are running.

This is required in bootstrap scenarios where:
  - SDN config was created but not yet applied, and
  - initial container starts failed and left CTs in "stopped" state.

Auth (API token only; values never printed):
  PM_API_URL / TF_VAR_pm_api_url
  PM_API_TOKEN_ID / TF_VAR_pm_api_token_id
  PM_API_TOKEN_SECRET / TF_VAR_pm_api_token_secret

This script is:
  - non-destructive (start-only)
  - idempotent
  - strict TLS (requires runner CA trust)
EOF
}

ENV_NAME="${1:-}"
if [[ -z "${ENV_NAME}" || "${ENV_NAME}" == "-h" || "${ENV_NAME}" == "--help" ]]; then
  usage
  exit 2
fi

api_url="${PM_API_URL:-${TF_VAR_pm_api_url:-}}"
token_id="${PM_API_TOKEN_ID:-${TF_VAR_pm_api_token_id:-}}"
token_secret="${PM_API_TOKEN_SECRET:-${TF_VAR_pm_api_token_secret:-}}"

if [[ -z "${api_url}" || -z "${token_id}" || -z "${token_secret}" ]]; then
  echo "ERROR: missing Proxmox API token env vars (PM_API_URL/PM_API_TOKEN_ID/PM_API_TOKEN_SECRET or TF_VAR_* equivalents)." >&2
  exit 1
fi

if [[ ! "${api_url}" =~ ^https:// ]]; then
  echo "ERROR: Proxmox API URL must be https:// (strict TLS): ${api_url}" >&2
  exit 1
fi

if [[ "${token_id}" != *"!"* ]]; then
  echo "ERROR: Proxmox token id must include '!': ${token_id}" >&2
  exit 1
fi

# Enforce strict TLS + token-only constraints (and verify host CA trust).
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/check-proxmox-ca-and-tls.sh" >/dev/null

python3 - <<'PY' "${FABRIC_REPO_ROOT}" "${ENV_NAME}" "${api_url}" "${token_id}" "${token_secret}"
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

repo_root = Path(sys.argv[1])
env_name = sys.argv[2]
api_url = sys.argv[3].rstrip("/")
token_id = sys.argv[4]
token_secret = sys.argv[5]

tf_env_dir = repo_root / "fabric-core" / "terraform" / "envs" / env_name
tf_output = tf_env_dir / "terraform-output.json"
if not tf_output.exists():
    raise SystemExit(f"ERROR: missing terraform output file: {tf_output} (run terraform apply first)")

payload = json.loads(tf_output.read_text(encoding="utf-8"))
lxc_inventory = payload.get("lxc_inventory", {}).get("value", {})
if not lxc_inventory:
    print("OK: lxc_inventory empty; nothing to start")
    raise SystemExit(0)

ctx = ssl.create_default_context()
headers = {"Authorization": f"PVEAPIToken={token_id}={token_secret}"}

def req(method: str, path: str, data: dict | None = None) -> dict:
    url = f"{api_url}{path}"
    body = None
    hdrs = dict(headers)
    if data is not None:
        body = urllib.parse.urlencode(data).encode("utf-8")
        hdrs["Content-Type"] = "application/x-www-form-urlencoded"
    r = urllib.request.Request(url, headers=hdrs, data=body, method=method)
    with urllib.request.urlopen(r, timeout=20, context=ctx) as resp:
        raw = resp.read().decode("utf-8")
    parsed = json.loads(raw) if raw else {}
    if isinstance(parsed, dict) and "data" in parsed:
        return parsed
    return {"data": parsed}

def status(node: str, vmid: int) -> str:
    data = req("GET", f"/nodes/{node}/lxc/{vmid}/status/current")["data"]
    return str(data.get("status") or "")

def start(node: str, vmid: int) -> None:
    req("POST", f"/nodes/{node}/lxc/{vmid}/status/start", data={})

def wait_running(node: str, vmid: int, timeout_seconds: int = 120) -> None:
    deadline = time.time() + timeout_seconds
    while True:
        st = status(node, vmid)
        if st == "running":
            return
        if time.time() > deadline:
            raise RuntimeError(f"{node}/{vmid}: did not reach running state (last status={st!r})")
        time.sleep(2)

for _, host in lxc_inventory.items():
    node = str(host["node"])
    vmid = int(host["vmid"])
    name = str(host.get("hostname") or f"{node}/{vmid}")
    st = status(node, vmid)
    if st == "running":
        print(f"OK: {name} already running ({node}/{vmid})")
        continue
    if st == "stopped":
        print(f"CHECK: starting {name} ({node}/{vmid})")
        try:
            start(node, vmid)
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="ignore")
            raise SystemExit(f"ERROR: failed to start {name} ({node}/{vmid}): HTTP {e.code}: {detail}") from None
        wait_running(node, vmid)
        print(f"OK: {name} running ({node}/{vmid})")
        continue
    raise SystemExit(f"ERROR: {name} unexpected status={st!r} ({node}/{vmid})")
PY
