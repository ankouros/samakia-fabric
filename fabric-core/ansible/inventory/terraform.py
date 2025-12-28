#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).parents[2]

ENV_NAME = os.environ.get("FABRIC_TERRAFORM_ENV") or "samakia-prod"
ENV_DIR = ROOT / "terraform" / "envs" / ENV_NAME
if not ENV_DIR.exists():
    raise SystemExit(f"ERROR: Terraform env directory not found: {ENV_DIR} (set FABRIC_TERRAFORM_ENV correctly)")

TF_OUTPUT = Path(os.environ.get("TF_OUTPUT_PATH", ENV_DIR / "terraform-output.json"))

inventory = {
    "_meta": {"hostvars": {}},
    "all": {"hosts": []},
}

HOST_VARS_DIR = ROOT / "ansible" / "host_vars"

def _env_first(*names: str) -> str | None:
    for name in names:
        value = os.environ.get(name)
        if value is not None and str(value).strip() != "":
            return value
    return None

def _load_host_vars(hostname: str) -> dict:
    path = HOST_VARS_DIR / f"{hostname}.yml"
    if not path.exists():
        return {}

    host_vars: dict[str, object] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip().strip("'").strip('"')
        if not key:
            continue
        host_vars[key] = value
    return host_vars

def _fetch_json(url: str, *, headers: dict[str, str]) -> dict:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=5) as resp:
        raw = resp.read()
    return json.loads(raw.decode("utf-8"))

def _fetch_json_retry(
    url: str,
    *,
    headers: dict[str, str],
    attempts: int = 8,
    delay_seconds: float = 1.0,
) -> dict | None:
    last_error: Exception | None = None
    for _ in range(attempts):
        try:
            return _fetch_json(url, headers=headers)
        except (urllib.error.URLError, ValueError) as exc:
            last_error = exc
            time.sleep(delay_seconds)
    return None

def _discover_lxc_ipv4(
    *,
    pm_api_url: str,
    node: str,
    vmid: int,
    token_id: str,
    token_secret: str,
) -> str | None:
    url = f"{pm_api_url.rstrip('/')}/nodes/{node}/lxc/{vmid}/interfaces"
    headers = {"Authorization": f"PVEAPIToken={token_id}={token_secret}"}

    payload = _fetch_json_retry(url, headers=headers)
    if not payload:
        return None

    for iface in payload.get("data", []):
        if iface.get("name") != "eth0":
            continue
        for addr in iface.get("ip-addresses", []):
            if addr.get("ip-address-type") != "inet":
                continue
            ip = addr.get("ip-address")
            if ip and ip != "127.0.0.1":
                return ip
    return None

data = None

try:
    result = subprocess.run(
        ["terraform", f"-chdir={ENV_DIR}", "output", "-json"],
        check=True,
        capture_output=True,
        text=True,
    )
    data = json.loads(result.stdout)
except Exception:
    if TF_OUTPUT.exists():
        data = json.loads(TF_OUTPUT.read_text())
    else:
        print(json.dumps(inventory, indent=2))
        exit(0)

lxc_inventory = data.get("lxc_inventory", {}).get("value", {})

pm_api_url = _env_first("TF_VAR_pm_api_url", "PM_API_URL")
pm_token_id = _env_first("TF_VAR_pm_api_token_id", "PM_API_TOKEN_ID")
pm_token_secret = _env_first("TF_VAR_pm_api_token_secret", "PM_API_TOKEN_SECRET")

errors: list[str] = []

for _, host in lxc_inventory.items():
    hostname = host["hostname"]
    inventory["all"]["hosts"].append(hostname)
    inventory["_meta"]["hostvars"][hostname] = {
        "proxmox_node": host["node"],
        "vmid": host["vmid"],
    }
    inventory["_meta"]["hostvars"][hostname].update(_load_host_vars(hostname))

    if "ansible_host" not in inventory["_meta"]["hostvars"][hostname]:
        if pm_api_url and pm_token_id and pm_token_secret:
            ip = _discover_lxc_ipv4(
                pm_api_url=pm_api_url,
                node=host["node"],
                vmid=int(host["vmid"]),
                token_id=pm_token_id,
                token_secret=pm_token_secret,
            )
            if ip:
                inventory["_meta"]["hostvars"][hostname]["ansible_host"] = ip
            else:
                errors.append(
                    f"{hostname}: failed to resolve IPv4 via Proxmox API (node={host['node']} vmid={host['vmid']}); ensure the container is running and DHCP reservation exists for the pinned MAC."
                )
        else:
            errors.append(
                f"{hostname}: ansible_host is not set and no Proxmox API credentials are available for IP discovery (set TF_VAR_pm_api_url + TF_VAR_pm_api_token_id + TF_VAR_pm_api_token_secret)."
            )

if errors:
    for line in errors:
        print(f"ERROR: {line}", file=sys.stderr)
    raise SystemExit(1)

print(json.dumps(inventory, indent=2))
