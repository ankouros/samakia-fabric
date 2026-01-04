#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

contract_path="${FABRIC_REPO_ROOT}/contracts/network/shared-plane.yml"
if [[ ! -f "${contract_path}" ]]; then
  echo "ERROR: shared-plane contract missing: ${contract_path}" >&2
  exit 1
fi

python3 - "${contract_path}" "${FABRIC_REPO_ROOT}" <<'PY'
import re
import sys
from pathlib import Path

contract_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])

lines = contract_path.read_text(encoding="utf-8").splitlines()

state = None
shared = {}
legacy = []
current = None

for raw in lines:
    stripped = raw.strip()
    if not stripped or stripped.startswith("#"):
        continue
    indent = len(raw) - len(raw.lstrip(" "))

    if stripped == "shared_plane:":
        state = "shared"
        current = None
        continue
    if stripped == "legacy_zones:":
        state = "legacy"
        current = None
        continue
    if stripped == "prohibited_patterns:":
        state = None
        current = None
        continue

    if state == "shared":
        if indent == 2 and stripped.startswith("zone:"):
            shared["zone"] = stripped.split(":", 1)[1].strip()
            continue
        if indent == 2 and stripped.startswith("vnet:"):
            shared["vnet"] = stripped.split(":", 1)[1].strip()
            continue

    if state == "legacy":
        if stripped.startswith("- zone:"):
            zone = stripped.split(":", 1)[1].strip()
            current = {"zone": zone}
            legacy.append(current)
            continue
        if current and indent >= 4 and stripped.startswith("vnet:"):
            current["vnet"] = stripped.split(":", 1)[1].strip()
            continue

missing = [key for key in ("zone", "vnet") if key not in shared]
if missing:
    raise SystemExit(
        "ERROR: shared-plane contract missing fields: " + ", ".join(missing)
    )

legacy_map = {}
for entry in legacy:
    zone = entry.get("zone")
    vnet = entry.get("vnet")
    if not zone or not vnet:
        raise SystemExit("ERROR: legacy_zones entries must include zone and vnet")
    legacy_map[zone] = vnet

zone_to_vnet = {shared["zone"]: shared["vnet"], **legacy_map}
allowed_zones = set(zone_to_vnet.keys())
allowed_vnets = set(zone_to_vnet.values())

legacy_allowlist = {
    "zonedns": {
        "fabric-core/terraform/envs/samakia-dns/main.tf",
        "ops/scripts/proxmox-sdn-ensure-dns-plane.sh",
        "ops/scripts/dns-sdn-accept.sh",
    },
    "vlandns": {
        "fabric-core/terraform/envs/samakia-dns/main.tf",
        "ops/scripts/proxmox-sdn-ensure-dns-plane.sh",
        "ops/scripts/dns-sdn-accept.sh",
    },
    "zminio": {
        "fabric-core/terraform/envs/samakia-minio/main.tf",
        "ops/scripts/proxmox-sdn-ensure-stateful-plane.sh",
        "ops/scripts/minio-sdn-accept.sh",
        "ops/scripts/minio-quorum-guard.sh",
    },
    "vminio": {
        "fabric-core/terraform/envs/samakia-minio/main.tf",
        "ops/scripts/proxmox-sdn-ensure-stateful-plane.sh",
        "ops/scripts/minio-sdn-accept.sh",
        "ops/scripts/minio-quorum-guard.sh",
    },
}

def check_legacy_use(token: str, path: Path, errors: list[str]) -> None:
    rel_path = path.relative_to(repo_root).as_posix()
    allowlist = legacy_allowlist.get(token)
    if allowlist is None:
        return
    if rel_path not in allowlist:
        errors.append(
            f"Legacy SDN token '{token}' used outside allowlist: {rel_path}"
        )

zone_patterns = [
    re.compile(r'^\s*(?:ZONE_NAME|SDN_ZONE|MINIO_SDN_ZONE)\s*=\s*"([^"]+)"'),
    re.compile(r"^\s*(?:ZONE_NAME|SDN_ZONE|MINIO_SDN_ZONE)\s*=\s*'([^']+)'"),
]
vnet_patterns = [
    re.compile(r'^\s*(?:VNET_NAME|SDN_VNET|MINIO_SDN_VNET)\s*=\s*"([^"]+)"'),
    re.compile(r"^\s*(?:VNET_NAME|SDN_VNET|MINIO_SDN_VNET)\s*=\s*'([^']+)'"),
]

errors = []

def scan_file(path: Path) -> None:
    zones = []
    vnets = []
    for line in path.read_text(encoding="utf-8").splitlines():
        for pattern in zone_patterns:
            match = pattern.match(line)
            if match:
                zones.append(match.group(1))
        for pattern in vnet_patterns:
            match = pattern.match(line)
            if match:
                vnets.append(match.group(1))

    for zone in zones:
        if zone not in allowed_zones:
            errors.append(
                f"Unsupported SDN zone '{zone}' in {path.relative_to(repo_root)}"
            )
        check_legacy_use(zone, path, errors)

    for vnet in vnets:
        if vnet not in allowed_vnets:
            errors.append(
                f"Unsupported SDN vnet '{vnet}' in {path.relative_to(repo_root)}"
            )
        check_legacy_use(vnet, path, errors)

    if zones and vnets:
        expected_vnets = {zone_to_vnet.get(zone) for zone in zones}
        expected_vnets.discard(None)
        for vnet in vnets:
            if expected_vnets and vnet not in expected_vnets:
                errors.append(
                    "SDN zone/vnet mismatch in "
                    f"{path.relative_to(repo_root)}: zones={zones}, vnets={vnets}"
                )

for path in (repo_root / "fabric-core/terraform/envs").rglob("*.tf"):
    scan_file(path)

for path in (repo_root / "ops/scripts").rglob("*.sh"):
    scan_file(path)

if errors:
    raise SystemExit("ERROR: shared-plane SDN policy violations:\n  - " + "\n  - ".join(sorted(errors)))

print("PASS: shared SDN plane governance enforced")
PY
