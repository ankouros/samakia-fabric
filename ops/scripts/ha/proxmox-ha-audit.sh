#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

POLICY_FILE="${FABRIC_REPO_ROOT}/fabric-core/ha/placement-policy.yml"

usage() {
  cat >&2 <<'EOT'
Usage:
  proxmox-ha-audit.sh

Read-only audit of Proxmox HA resources. Fails if HA resources
exist while policy expects none, or if policy expects HA but none exist.
EOT
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "${POLICY_FILE}" ]]; then
  echo "ERROR: placement policy not found: ${POLICY_FILE}" >&2
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

python3 - "${POLICY_FILE}" "${tmp_payload}" <<'PY'
import json
import sys

policy_path = sys.argv[1]
payload_path = sys.argv[2]
try:
    policy = json.load(open(policy_path, "r", encoding="utf-8"))
except Exception as exc:
    print(f"FAIL: could not parse placement policy: {exc}", file=sys.stderr)
    sys.exit(1)

envs = policy.get("envs", {}) or {}
expected_any = any(env.get("proxmox_ha_expected") for env in envs.values() if isinstance(env, dict))

try:
    payload = json.load(open(payload_path, "r", encoding="utf-8"))
except Exception as exc:
    print(f"FAIL: could not parse Proxmox HA response: {exc}", file=sys.stderr)
    sys.exit(1)
resources = payload.get("data", []) or []

if resources:
    print("INFO: Proxmox HA resources detected:")
    for res in resources:
        rid = res.get("sid") or res.get("id") or res.get("resource") or "unknown"
        group = res.get("group") or "(none)"
        state = res.get("state") or res.get("status") or "unknown"
        print(f"- {rid} group={group} state={state}")

if expected_any and not resources:
    print("FAIL: placement policy expects Proxmox HA resources, but none are configured", file=sys.stderr)
    sys.exit(1)

if not expected_any and resources:
    print("FAIL: Proxmox HA resources exist, but placement policy expects none", file=sys.stderr)
    sys.exit(1)

print("PASS: Proxmox HA audit matches placement policy")
PY
rm -f "${tmp_payload}"
