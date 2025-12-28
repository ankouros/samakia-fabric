#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  ha-sim-verify.sh <ctid>

Read-only verification helper for HA simulations.

Prints (best-effort):
  - current node placement (via pvesh cluster/resources if available)
  - CT status (pct status)
  - HA resource line(s) (pve-ha-manager/ha-manager status)
  - recent HA-related journal excerpts filtered by CTID (read-only)

Hard rules:
  - No writes.
  - No network calls.
  - Does not SSH into containers.
EOF
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

ctid="${1:-}"
if [[ -z "${ctid}" ]]; then
  usage
  exit 2
fi

require_cmd awk
require_cmd grep
require_cmd sed

echo "== CT placement (best-effort) =="
if command -v pvesh >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  json="$(pvesh get /cluster/resources --type lxc --output-format json 2>/dev/null || true)"
  if [[ -n "${json}" ]]; then
    tmp_json="$(mktemp)"
    printf '%s' "${json}" >"${tmp_json}"
    python3 - "${ctid}" "${tmp_json}" <<'PY' || true
import json
import sys

ctid = sys.argv[1]
json_path = sys.argv[2]
data = json.loads(open(json_path, "r", encoding="utf-8").read())
for item in data:
  if str(item.get("vmid")) == str(ctid):
    node = item.get("node") or "unknown"
    status = item.get("status") or "unknown"
    name = item.get("name") or "unknown"
    print(f"node={node} status={status} name={name}")
    raise SystemExit(0)
print("node=unknown status=unknown name=unknown")
PY
    rm -f "${tmp_json}" || true
  else
    echo "node=unknown status=unknown name=unknown (pvesh returned no data)"
  fi
else
  echo "node=unknown status=unknown name=unknown (pvesh/python3 not available)"
fi

echo
echo "== pct status =="
if command -v pct >/dev/null 2>&1; then
  pct status "${ctid}" 2>/dev/null || echo "pct status failed for ${ctid}"
else
  echo "pct not available on this host"
fi

echo
echo "== HA resource status =="
if command -v pve-ha-manager >/dev/null 2>&1; then
  pve-ha-manager status 2>/dev/null | grep -E "lxc:${ctid}\\b" || echo "no HA line found for lxc:${ctid}"
elif command -v ha-manager >/dev/null 2>&1; then
  ha-manager status 2>/dev/null | grep -E "lxc:${ctid}\\b" || echo "no HA line found for lxc:${ctid}"
else
  echo "HA manager CLI not available (pve-ha-manager/ha-manager missing)"
fi

echo
echo "== Recent HA-related logs (best-effort, read-only) =="
if command -v journalctl >/dev/null 2>&1; then
  journalctl -u pve-ha-crm -u pve-ha-lrm --no-pager -n 200 2>/dev/null \
    | grep -E "(lxc:${ctid}\\b|\\b${ctid}\\b)" || echo "no matching HA log lines in last 200 entries"
else
  echo "journalctl not available"
fi
