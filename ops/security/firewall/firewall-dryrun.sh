#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

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

rendered="$(mktemp)"
trap 'rm -f "${rendered}"' EXIT

while IFS= read -r line; do
  if [[ "${line}" == "    # ALLOWLIST" ]]; then
    cat "${allowlist_path}" >>"${rendered}"
  else
    echo "${line}" >>"${rendered}"
  fi
done <"${profile_path}"

if ! command -v nft >/dev/null 2>&1; then
  echo "ERROR: nft not found (required for firewall dry-run)" >&2
  exit 1
fi

check_cmd=(nft -c -f "${rendered}")
if [[ $(id -u) -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "ERROR: root privileges required for nft --check; sudo not available" >&2
    exit 2
  fi
  check_cmd=(sudo -n nft -c -f "${rendered}")
fi

if ! "${check_cmd[@]}" >/dev/null; then
  echo "ERROR: nft check failed (operation not permitted or invalid ruleset)" >&2
  exit 2
fi

echo "OK: firewall profile syntax is valid (${profile})"
