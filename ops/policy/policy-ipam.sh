#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

contract_path="${FABRIC_REPO_ROOT}/contracts/network/ipam-shared.yml"
if [[ ! -f "${contract_path}" ]]; then
  echo "ERROR: IPAM contract missing: ${contract_path}" >&2
  exit 1
fi

python3 - "${contract_path}" "${FABRIC_REPO_ROOT}" <<'PY'
import ipaddress
import re
import subprocess
import sys
from pathlib import Path

contract_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])

text = contract_path.read_text(encoding="utf-8")
lines = text.splitlines()

network = {}
ranges = {}
vip_registry = {}
state = None
current = None

for line in lines:
    raw = line.rstrip("\n")
    stripped = raw.strip()
    if not stripped or stripped.startswith("#"):
        continue

    indent = len(raw) - len(raw.lstrip(" "))

    if stripped == "network:":
        state = "network"
        current = None
        continue
    if stripped == "vip_registry:":
        state = "vip_registry"
        current = None
        continue
    if stripped in ("dns_policy:", "consumers:"):
        state = None
        current = None
        continue

    if state == "network":
        if indent == 2 and stripped == "ranges:":
            state = "ranges"
            current = None
            continue
        if indent == 2 and stripped.startswith("vlan_id:"):
            network["vlan_id"] = stripped.split(":", 1)[1].strip()
            continue
        if indent == 2 and stripped.startswith("cidr:"):
            network["cidr"] = stripped.split(":", 1)[1].strip()
            continue

    if state == "ranges":
        if indent == 4 and stripped.endswith(":"):
            current = stripped[:-1]
            continue
        if current and indent == 6 and stripped.startswith("cidr:"):
            ranges[current] = stripped.split(":", 1)[1].strip()
            continue

    if state == "vip_registry":
        if indent == 2 and stripped.endswith(":"):
            current = stripped[:-1]
            continue
        if current and indent == 4 and stripped.startswith("vip:"):
            vip_registry[current] = stripped.split(":", 1)[1].strip()
            continue

missing = [key for key in ("cidr",) if key not in network]
if missing:
    raise SystemExit(f"ERROR: ipam-shared.yml missing network fields: {', '.join(missing)}")

required_ranges = {"management", "workload", "proxy", "vip"}
missing_ranges = required_ranges - set(ranges.keys())
if missing_ranges:
    raise SystemExit(f"ERROR: ipam-shared.yml missing ranges: {', '.join(sorted(missing_ranges))}")

vlan_network = ipaddress.ip_network(network["cidr"])

def parse_block(cidr: str, label: str):
    if "/" not in cidr:
        raise SystemExit(f"ERROR: {label} range missing CIDR prefix: {cidr}")
    ip_str, prefix_str = cidr.split("/", 1)
    try:
        start_ip = ipaddress.ip_address(ip_str)
    except ValueError:
        raise SystemExit(f"ERROR: {label} range invalid IP: {cidr}")
    if start_ip.version != 4:
        raise SystemExit(f"ERROR: {label} range must be IPv4: {cidr}")
    try:
        prefix = int(prefix_str)
    except ValueError:
        raise SystemExit(f"ERROR: {label} range invalid prefix: {cidr}")
    if prefix < 0 or prefix > 32:
        raise SystemExit(f"ERROR: {label} range invalid prefix: {cidr}")
    size = 2 ** (32 - prefix)
    start_int = int(start_ip)
    end_int = start_int + size - 1
    if end_int >= 2 ** 32:
        raise SystemExit(f"ERROR: {label} range exceeds IPv4 space: {cidr}")
    end_ip = ipaddress.ip_address(end_int)
    if start_ip not in vlan_network or end_ip not in vlan_network:
        raise SystemExit(f"ERROR: {label} range outside shared VLAN: {cidr}")
    return {
        "cidr": cidr,
        "start": start_int,
        "end": end_int,
        "start_ip": start_ip,
        "end_ip": end_ip,
    }

range_blocks = {name: parse_block(cidr, name) for name, cidr in ranges.items()}

sorted_ranges = sorted(range_blocks.items(), key=lambda item: item[1]["start"])
for idx in range(1, len(sorted_ranges)):
    prev_name, prev_block = sorted_ranges[idx - 1]
    curr_name, curr_block = sorted_ranges[idx]
    if curr_block["start"] <= prev_block["end"]:
        raise SystemExit(
            "ERROR: IPAM ranges overlap: "
            f"{prev_name} ({prev_block['cidr']}) and {curr_name} ({curr_block['cidr']})"
        )

vip_range = range_blocks["vip"]

vip_values = list(vip_registry.values())
if len(set(vip_values)) != len(vip_values):
    raise SystemExit("ERROR: VIP registry contains duplicate IPs")

vip_outside = [
    vip
    for vip in vip_values
    if not (vip_range["start"] <= int(ipaddress.ip_address(vip)) <= vip_range["end"])
]
if vip_outside:
    raise SystemExit(f"ERROR: VIPs outside vip range: {', '.join(vip_outside)}")

ignore_ips = set()
ignore_ips.add(str(vlan_network.network_address))
ignore_ips.add(str(vlan_network.broadcast_address))

pattern = r"\b(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?\b"
try:
    rg = subprocess.run(
        ["rg", "-o", "-N", pattern, str(repo_root)],
        capture_output=True,
        text=True,
        check=False,
    )
except FileNotFoundError:
    raise SystemExit("ERROR: rg is required for IPAM policy checks")

if rg.returncode not in (0, 1):
    raise SystemExit(rg.stderr.strip() or "ERROR: rg failed during IP scan")

tokens = {line.strip() for line in rg.stdout.splitlines() if line.strip()}

errors = []

for token in tokens:
    ip_part = token.split("/", 1)[0]
    try:
        ip = ipaddress.ip_address(ip_part)
    except ValueError:
        continue
    if ip.version != 4:
        continue

    if ip_part in ignore_ips:
        continue

    if "/" in token:
        try:
            prefix = int(token.split("/", 1)[1])
        except ValueError:
            prefix = None
        if prefix is not None and prefix < 32:
            net = ipaddress.ip_network(token, strict=False)
            if ip == net.network_address:
                continue

    if ip not in vlan_network:
        continue

    ip_int = int(ip)
    if not any(block["start"] <= ip_int <= block["end"] for block in range_blocks.values()):
        errors.append(f"IP outside shared ranges: {ip}")
        continue

    if vip_range["start"] <= ip_int <= vip_range["end"] and ip_part not in vip_registry.values():
        errors.append(f"VIP used outside registry: {ip}")

if errors:
    raise SystemExit("ERROR: ipam policy violations:\n  - " + "\n  - ".join(sorted(errors)))

# DNS policy check: VIPs must not appear in DNS record definitions.
dns_defaults = repo_root / "fabric-core/ansible/roles/dns_auth_powerdns/defaults/main.yml"
if dns_defaults.exists():
    dns_text = dns_defaults.read_text(encoding="utf-8")
    dns_ips = set(re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", dns_text))
    dns_hits = sorted(set(vip_values) & dns_ips)
    if dns_hits:
        raise SystemExit(
            "ERROR: VIPs referenced in DNS records (proxy-first required): "
            + ", ".join(dns_hits)
        )

print("PASS: shared VLAN IP/VIP allocation contract enforced")
PY
