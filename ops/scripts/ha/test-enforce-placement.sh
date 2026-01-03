#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

policy_path="$tmp_dir/policy.json"
inventory_path="$tmp_dir/inventory.json"

cat >"$policy_path" <<'JSON'
{
  "version": 1,
  "failure_domains": {
    "nodes": ["proxmox1", "proxmox2"]
  },
  "tiers": {
    "tier0": {"description": "tier0", "ha_semantics": "vip", "expected_recovery": "seconds"},
    "tier1": {"description": "tier1", "ha_semantics": "app", "expected_recovery": "minutes"},
    "tier2": {"description": "tier2", "ha_semantics": "best-effort", "expected_recovery": "hours"}
  },
  "envs": {
    "test-env": {
      "proxmox_ha_expected": false,
      "workloads": [
        {
          "name": "edge",
          "tier": "tier0",
          "ha_mode": "vip",
          "replicas": 2,
          "anti_affinity": true,
          "hosts": ["edge-1", "edge-2"]
        },
        {
          "name": "core",
          "tier": "tier1",
          "ha_mode": "app",
          "replicas": 1,
          "anti_affinity": false,
          "hosts": ["core-1"]
        }
      ]
    }
  }
}
JSON

cat >"$inventory_path" <<'JSON'
{
  "_meta": {
    "hostvars": {
      "edge-1": {"proxmox_node": "proxmox1"},
      "edge-2": {"proxmox_node": "proxmox1"},
      "core-1": {"proxmox_node": "proxmox2"}
    }
  },
  "all": {
    "hosts": ["edge-1", "edge-2", "core-1"]
  }
}
JSON

set +e
bash "${FABRIC_REPO_ROOT}/ops/scripts/ha/enforce-placement.sh" \
  --env test-env \
  --policy "$policy_path" \
  --inventory-json "$inventory_path" >/dev/null 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: enforcement should fail without override" >&2
  exit 1
fi

output="$(
  HA_OVERRIDE=1 HA_OVERRIDE_REASON="unit-test override" \
    bash "${FABRIC_REPO_ROOT}/ops/scripts/ha/enforce-placement.sh" \
      --env test-env \
      --policy "$policy_path" \
      --inventory-json "$inventory_path"
)"

if ! grep -q "FAIL-OVERRIDDEN" <<<"$output"; then
  echo "FAIL: expected FAIL-OVERRIDDEN in override output" >&2
  exit 1
fi

echo "PASS: enforcement override path verified"
