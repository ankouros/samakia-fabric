#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

ZONE_NAME="zonedns"
ZONE_TYPE="vlan"
ZONE_BRIDGE="vmbr0"

VNET_NAME="vlandns"
VLAN_TAG="100"

SUBNET_CIDR="10.10.100.0/24"
SUBNET_GATEWAY="10.10.100.1"
SUBNET_TYPE="subnet"

usage() {
  cat >&2 <<EOF
Usage:
  proxmox-sdn-ensure-dns-plane.sh
  proxmox-sdn-ensure-dns-plane.sh --apply
  proxmox-sdn-ensure-dns-plane.sh --check-only

Ensures Proxmox SDN primitives exist for the DNS VLAN plane (idempotent, strict TLS):
  - zone:   ${ZONE_NAME} (type=${ZONE_TYPE}, bridge=${ZONE_BRIDGE})
  - vnet:   ${VNET_NAME} (tag=${VLAN_TAG})
  - subnet: ${SUBNET_CIDR} (gateway=${SUBNET_GATEWAY})

Auth (API token only; values never printed):
  PM_API_URL / TF_VAR_pm_api_url
  PM_API_TOKEN_ID / TF_VAR_pm_api_token_id
  PM_API_TOKEN_SECRET / TF_VAR_pm_api_token_secret

Behavior:
  - Create if missing
  - Validate shape if present
  - Fail loudly on mismatch (no dangerous mutation)
  - If any change is made, apply SDN config cluster-wide (required before it can be used)
  - --apply forces an apply even if no changes are made (safe and idempotent)

EOF
}

check_only=0
force_apply=0

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--apply" ]]; then
  force_apply=1
  shift
fi

if [[ "${1:-}" == "--check-only" ]]; then
  check_only=1
  shift
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

python3 - <<'PY' \
  "${api_url}" "${token_id}" "${token_secret}" \
  "${ZONE_NAME}" "${ZONE_TYPE}" "${ZONE_BRIDGE}" \
  "${VNET_NAME}" "${VLAN_TAG}" \
  "${SUBNET_CIDR}" "${SUBNET_GATEWAY}" "${SUBNET_TYPE}" "${check_only}" "${force_apply}"
import json
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
import time

api_url, token_id, token_secret, zone_name, zone_type, zone_bridge, vnet_name, vlan_tag, subnet_cidr, subnet_gw, subnet_type, check_only_s, force_apply_s = sys.argv[1:]
check_only = check_only_s == "1"
force_apply = force_apply_s == "1"

base = api_url.rstrip("/")
ctx = ssl.create_default_context()
auth = {"Authorization": f"PVEAPIToken={token_id}={token_secret}"}

def _req(method: str, path: str, data: dict | None = None) -> dict:
    url = f"{base}{path}"
    headers = dict(auth)
    body = None
    if data is not None:
        body = urllib.parse.urlencode(data).encode("utf-8")
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15, context=ctx) as resp:
            raw = resp.read().decode("utf-8")
        parsed = json.loads(raw) if raw else {}
        if isinstance(parsed, dict) and "data" in parsed:
            return parsed
        return {"data": parsed}
    except urllib.error.HTTPError as e:
        msg = e.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"{method} {path} -> HTTP {e.code}: {msg or str(e)}") from None

def get(path: str) -> list[dict]:
    payload = _req("GET", path)
    data = payload.get("data")
    if data is None:
        return []
    if not isinstance(data, list):
        raise RuntimeError(f"GET {path}: expected list, got {type(data).__name__}")
    return [x for x in data if isinstance(x, dict)]

def post(path: str, data: dict) -> None:
    if check_only:
        raise RuntimeError(f"check-only mode: refusing to create {path}")
    _req("POST", path, data=data)

def find_by_key(items: list[dict], key: str, value: str) -> dict | None:
    for item in items:
        if str(item.get(key, "")) == value:
            return item
    return None

def apply_sdn(timeout_seconds: int = 180) -> None:
    if check_only:
        raise RuntimeError("check-only mode: refusing to apply SDN config")
    payload = _req("PUT", "/cluster/sdn", data={})
    upid = payload.get("data")
    if not isinstance(upid, str) or not upid.startswith("UPID:"):
        raise RuntimeError(f"SDN apply did not return UPID: {upid!r}")

    node = upid.split(":", 2)[1] if ":" in upid else ""
    if not node:
        raise RuntimeError(f"failed to parse node from UPID: {upid}")

    deadline = time.time() + timeout_seconds
    upid_quoted = urllib.parse.quote(upid, safe="")
    while True:
        st = _req("GET", f"/nodes/{node}/tasks/{upid_quoted}/status").get("data", {})
        status = st.get("status")
        exitstatus = st.get("exitstatus")
        if status == "stopped":
            if exitstatus == "OK":
                return
            raise RuntimeError(f"SDN apply failed (UPID={upid}) exitstatus={exitstatus}")
        if time.time() > deadline:
            raise RuntimeError(f"SDN apply timed out (UPID={upid})")
        time.sleep(2)

changes: list[str] = []

def main() -> None:
    # 1) Zone
    zones = get("/cluster/sdn/zones")
    zone = find_by_key(zones, "zone", zone_name) or find_by_key(zones, "name", zone_name)
    if not zone:
        post("/cluster/sdn/zones", {"zone": zone_name, "type": zone_type, "bridge": zone_bridge})
        changes.append(f"created zone={zone_name}")
        zones = get("/cluster/sdn/zones")
        zone = find_by_key(zones, "zone", zone_name) or find_by_key(zones, "name", zone_name)
    if not zone:
        raise RuntimeError(f"zone creation failed or not visible: {zone_name}")

    actual_type = str(zone.get("type", ""))
    actual_bridge = str(zone.get("bridge", ""))
    if actual_type and actual_type != zone_type:
        raise RuntimeError(f"zone mismatch: {zone_name} type expected={zone_type} got={actual_type}")
    if actual_bridge and actual_bridge != zone_bridge:
        raise RuntimeError(f"zone mismatch: {zone_name} bridge expected={zone_bridge} got={actual_bridge}")

    # 2) VNet
    vnets = get("/cluster/sdn/vnets")
    vnet = find_by_key(vnets, "vnet", vnet_name) or find_by_key(vnets, "name", vnet_name)
    if not vnet:
        post("/cluster/sdn/vnets", {"vnet": vnet_name, "zone": zone_name, "tag": vlan_tag})
        changes.append(f"created vnet={vnet_name}")
        vnets = get("/cluster/sdn/vnets")
        vnet = find_by_key(vnets, "vnet", vnet_name) or find_by_key(vnets, "name", vnet_name)
    if not vnet:
        raise RuntimeError(f"vnet creation failed or not visible: {vnet_name}")

    actual_zone = str(vnet.get("zone", ""))
    if actual_zone and actual_zone != zone_name:
        raise RuntimeError(f"vnet mismatch: {vnet_name} zone expected={zone_name} got={actual_zone}")

    actual_tag = str(vnet.get("tag", ""))
    if actual_tag and actual_tag != vlan_tag:
        raise RuntimeError(f"vnet mismatch: {vnet_name} tag expected={vlan_tag} got={actual_tag}")

    # 3) Subnet (vnet-scoped)
    subnets = get(f"/cluster/sdn/vnets/{vnet_name}/subnets")
    subnet = find_by_key(subnets, "cidr", subnet_cidr) or find_by_key(subnets, "subnet", subnet_cidr)
    if not subnet:
        post(f"/cluster/sdn/vnets/{vnet_name}/subnets", {"subnet": subnet_cidr, "gateway": subnet_gw, "type": subnet_type})
        changes.append(f"created subnet={subnet_cidr}")
        subnets = get(f"/cluster/sdn/vnets/{vnet_name}/subnets")
        subnet = find_by_key(subnets, "cidr", subnet_cidr) or find_by_key(subnets, "subnet", subnet_cidr)
    if not subnet:
        raise RuntimeError(f"subnet creation failed or not visible: {subnet_cidr}")

    actual_type = str(subnet.get("type", ""))
    if actual_type and actual_type != subnet_type:
        raise RuntimeError(f"subnet mismatch: {subnet_cidr} type expected={subnet_type} got={actual_type}")

    actual_gw = str(subnet.get("gateway", ""))
    if actual_gw and actual_gw != subnet_gw:
        raise RuntimeError(f"subnet mismatch: {subnet_cidr} gateway expected={subnet_gw} got={actual_gw}")

    if check_only:
        print("OK: SDN DNS plane present (check-only)")
        return

    if changes or force_apply:
        apply_sdn()
        if changes:
            print("OK: SDN DNS plane ensured + applied (" + ", ".join(changes) + ")")
        else:
            print("OK: SDN DNS plane applied (no config changes)")
        return

    print("OK: SDN DNS plane already present (no changes)")

try:
    main()
except Exception as e:
    msg = str(e).strip()
    if "HTTP 403" in msg and "Permission check failed" in msg:
        m = re.search(r"Permission check failed \\(([^,]+),\\s*([^\\)]+)\\)", msg)
        if m:
            missing_path = m.group(1).strip()
            missing_priv = m.group(2).strip()
        else:
            missing_path = "/cluster/sdn/*"
            missing_priv = "SDN.*"

        if missing_priv == "SDN.Allocate":
            print(
                (
                    "ERROR: Proxmox API token lacks required SDN privilege (SDN.Allocate) to create SDN primitives.\n"
                    "Fix: grant SDN.Allocate to the token OR pre-create the SDN plane:\n"
                    f"  zone={zone_name} type={zone_type} bridge={zone_bridge}\n"
                    f"  vnet={vnet_name} tag={vlan_tag}\n"
                    f"  subnet={subnet_cidr} gateway={subnet_gw}\n"
                    "Then re-run the same command."
                ),
                file=sys.stderr,
            )
            sys.exit(1)

        print(
            (
                "ERROR: Proxmox API token lacks required privilege to read/modify SDN primitives.\n"
                f"Missing privilege: {missing_priv}\n"
                f"Scope/path: {missing_path}\n"
                "Fix: grant the missing privilege to the token (or use an operator token to pre-create/validate the SDN plane), then re-run."
            ),
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)
PY
