#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


errors=0

lxc_packer="$FABRIC_REPO_ROOT/fabric-core/packer/lxc/ubuntu-24.04/packer.pkr.hcl"
if ! rg -n "default = \"https://snapshot\.ubuntu\.com/ubuntu/" "$lxc_packer" >/dev/null; then
  echo "FAIL: LXC apt snapshot default is not pinned in $lxc_packer" >&2
  errors=$((errors + 1))
fi

lxc_provision="$FABRIC_REPO_ROOT/fabric-core/packer/lxc/ubuntu-24.04/provision.sh"
if ! rg -n "snapshot\.ubuntu\.com" "$lxc_provision" >/dev/null; then
  echo "FAIL: LXC provisioner does not reference snapshot.ubuntu.com" >&2
  errors=$((errors + 1))
fi

check_snapshot_value() {
  local file="$1"
  local key="$2"
  local value
  value="$(awk -F'"' -v k="$key" '$1 ~ "^"k" " {print $2}' "$file" | head -n 1)"
  if [[ -z "$value" ]]; then
    echo "FAIL: $key missing or empty in $file" >&2
    errors=$((errors + 1))
    return
  fi
  if [[ ! "$value" =~ [0-9]{8}T[0-9]{6}Z ]]; then
    echo "FAIL: $key value is not timestamp-pinned in $file -> $value" >&2
    errors=$((errors + 1))
  fi
}

check_snapshot_value "$FABRIC_REPO_ROOT/images/packer/ubuntu-24.04/v1/ubuntu24.pkrvars.hcl" "apt_snapshot_url"
check_snapshot_value "$FABRIC_REPO_ROOT/images/packer/ubuntu-24.04/v1/ubuntu24.pkrvars.hcl" "apt_snapshot_security_url"
check_snapshot_value "$FABRIC_REPO_ROOT/images/packer/debian-12/v1/debian12.pkrvars.hcl" "apt_snapshot_url"
check_snapshot_value "$FABRIC_REPO_ROOT/images/packer/debian-12/v1/debian12.pkrvars.hcl" "apt_snapshot_security_url"

if [[ "$errors" -gt 0 ]]; then
  exit 1
fi

echo "PASS: apt snapshot pinning validated"
