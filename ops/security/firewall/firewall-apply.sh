#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ "${FIREWALL_ENABLE:-0}" -ne 1 || "${FIREWALL_EXECUTE:-0}" -ne 1 ]]; then
  echo "ERROR: firewall apply requires FIREWALL_ENABLE=1 and FIREWALL_EXECUTE=1" >&2
  exit 2
fi

profile="${FIREWALL_PROFILE:-baseline}"
profile_path="${FABRIC_REPO_ROOT}/ops/security/firewall/profiles/${profile}.nft"
allowlist_path="${FIREWALL_ALLOWLIST:-${FABRIC_REPO_ROOT}/ops/security/firewall/allowlist.nft}"

if [[ ! -f "${profile_path}" ]]; then
  echo "ERROR: firewall profile not found: ${profile_path}" >&2
  exit 2
fi

if [[ ! -f "${allowlist_path}" ]]; then
  echo "ERROR: allowlist not found: ${allowlist_path}" >&2
  exit 2
fi

if ! command -v nft >/dev/null 2>&1; then
  echo "ERROR: nft not found (required for firewall apply)" >&2
  exit 1
fi

rendered="$(mktemp)"
trap 'rm -f "${rendered}"' EXIT

while IFS= read -r line; do
  if [[ "${line}" == "    # ALLOWLIST" ]]; then
    cat "${allowlist_path}" >>"${rendered}"
  else
    echo "${line}" >>"${rendered}"
  fi
done <"${profile_path}"

apply_cmd=(nft -f "${rendered}")
if [[ $(id -u) -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "ERROR: root privileges required for nft; sudo not available" >&2
    exit 2
  fi
  apply_cmd=(sudo -n nft -f "${rendered}")
fi

if ! "${apply_cmd[@]}"; then
  echo "ERROR: nft apply failed (operation not permitted or invalid ruleset)." >&2
  echo "Hint: run with sufficient privileges or verify LXC capabilities." >&2
  exit 2
fi

echo "OK: firewall profile applied (${profile})"
