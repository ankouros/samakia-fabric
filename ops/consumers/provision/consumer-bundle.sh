#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  consumer-bundle.sh [--consumer <contract.yml>] [--out <dir>]

Generates consumer bundles under:
  artifacts/consumer-bundles/<UTC>/<consumer-name>/

No secrets are written.
EOT
}

CONSUMER_PATH=""
OUT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --consumer)
      CONSUMER_PATH="${2:-}"
      shift 2
      ;;
    --out)
      OUT_ROOT="${2:-}"
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

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -z "${OUT_ROOT}" ]]; then
  OUT_ROOT="${FABRIC_REPO_ROOT}/artifacts/consumer-bundles/${stamp}"
fi

if [[ -n "${CONSUMER_PATH}" ]]; then
  contracts=("${CONSUMER_PATH}")
else
  mapfile -t contracts < <(find "${FABRIC_REPO_ROOT}/contracts/consumers" -mindepth 2 -maxdepth 2 -name "*.yml" -print | sort)
fi

if [[ ${#contracts[@]} -eq 0 ]]; then
  echo "ERROR: no consumer contracts found" >&2
  exit 1
fi

for contract in "${contracts[@]}"; do
  if [[ ! -f "${contract}" ]]; then
    echo "ERROR: contract not found: ${contract}" >&2
    exit 1
  fi

  CONTRACT_PATH="${contract}" OUT_ROOT="${OUT_ROOT}" python3 - <<'PY'
import json
import os
from pathlib import Path

contract_path = Path(os.environ["CONTRACT_PATH"])
contract = json.loads(contract_path.read_text())

spec = contract["spec"]
name = contract["metadata"]["name"]

out_root = Path(os.environ["OUT_ROOT"])

bundle_dir = out_root / name
bundle_dir.mkdir(parents=True, exist_ok=True)

bundle = {
    "name": name,
    "type": spec["type"],
    "variant": spec["variant"],
    "network": {
        "planes": spec["network"]["planes"],
        "vip": spec["network"]["vip"],
        "ports": spec["network"]["ports"],
    },
    "storage": spec["storage"],
    "firewall": spec["firewall"],
    "observability": spec["observability"],
    "disaster": spec["disaster"],
}

(bundle_dir / "bundle.json").write_text(json.dumps(bundle, indent=2, sort_keys=True) + "\n")

bundle_md = [
    "# Consumer Bundle",
    "",
    f"- name: {name}",
    f"- type: {spec['type']}",
    f"- variant: {spec['variant']}",
    "",
    "## Network",
    f"- vip required: {spec['network']['vip']['required']}",
    f"- ports: {len(spec['network']['ports'])}",
    "",
    "## Storage",
    f"- backend: {spec['storage']['backend']}",
    f"- class: {spec['storage']['class']}",
    "",
    "## Firewall",
    f"- default_off: {spec['firewall']['default_off']}",
    f"- profile: {spec['firewall']['profile']}",
    "",
    "## Observability",
    f"- metrics endpoints: {len(spec['observability']['metrics'])}",
    f"- log labels: {', '.join(spec['observability']['logs']['labels'])}",
    "",
    "## Disaster",
    f"- scenarios: {len(spec['disaster']['scenarios'])}",
]

(bundle_dir / "bundle.md").write_text("\n".join(bundle_md) + "\n")

ports_lines = []
for port in spec["network"]["ports"]:
    ports_lines.append(f"{port['name']} {port['port']}/{port['protocol']}")
(bundle_dir / "ports.txt").write_text("\n".join(ports_lines) + "\n")

(bundle_dir / "observability-labels.txt").write_text("\n".join(spec["observability"]["logs"]["labels"]) + "\n")

firewall_lines = [
    "# Firewall intents (do not apply directly)",
    f"default_off: {spec['firewall']['default_off']}",
    f"profile: {spec['firewall']['profile']}",
    f"enable_guard: {', '.join(spec['firewall']['enable_guard'])}",
]
(bundle_dir / "firewall-intents.md").write_text("\n".join(firewall_lines) + "\n")

storage_lines = [
    "# Storage contract",
    f"backend: {spec['storage']['backend']}",
    f"class: {spec['storage']['class']}",
    f"backup_hooks: {', '.join(spec['storage'].get('backup_hooks', []))}",
]
(bundle_dir / "storage-contract.md").write_text("\n".join(storage_lines) + "\n")

scenarios = []
for scenario in spec["disaster"]["scenarios"]:
    name = scenario.get("name")
    testcases = ", ".join(scenario.get("testcases", []))
    scenarios.append(f"{name}: {testcases}")

(bundle_dir / "disaster-testcases.md").write_text("\n".join(scenarios) + "\n")

print(f"OK: bundle -> {bundle_dir}")
PY

done
