#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

errors=0

lxc_provision="$FABRIC_REPO_ROOT/fabric-core/packer/lxc/ubuntu-24.04/provision.sh"
for key in IMAGE_NAME IMAGE_VERSION BUILD_UTC GIT_SHA PACKER_TEMPLATE BASE_IMAGE_DIGEST APT_SNAPSHOT; do
  if ! rg -n "${key}=" "$lxc_provision" >/dev/null; then
    echo "FAIL: missing ${key} in LXC provenance stamp ($lxc_provision)" >&2
    errors=$((errors + 1))
  fi
done

if ! rg -n "chmod 0444 /etc/samakia-image-version" "$lxc_provision" >/dev/null; then
  echo "FAIL: LXC provenance file is not set to 0444" >&2
  errors=$((errors + 1))
fi

if ! rg -n "chattr \+i /etc/samakia-image-version" "$lxc_provision" >/dev/null; then
  echo "FAIL: LXC provenance file is not immutable" >&2
  errors=$((errors + 1))
fi

vm_template="$FABRIC_REPO_ROOT/images/ansible/roles/golden_base/templates/image-version.txt.j2"
for key in IMAGE_NAME IMAGE_VERSION BUILD_UTC GIT_SHA PACKER_TEMPLATE BASE_IMAGE_DIGEST APT_SNAPSHOT; do
  if ! rg -n "${key}=" "$vm_template" >/dev/null; then
    echo "FAIL: missing ${key} in VM provenance template ($vm_template)" >&2
    errors=$((errors + 1))
  fi
done

vm_tasks="$FABRIC_REPO_ROOT/images/ansible/roles/golden_base/tasks/main.yml"
if ! rg -n "mode: \"0444\"" "$vm_tasks" >/dev/null; then
  echo "FAIL: VM provenance file is not set to 0444" >&2
  errors=$((errors + 1))
fi

if ! rg -n "chattr \+i /etc/samakia-image-version" "$vm_tasks" >/dev/null; then
  echo "FAIL: VM provenance file is not immutable" >&2
  errors=$((errors + 1))
fi

if [[ "$errors" -gt 0 ]]; then
  exit 1
fi

echo "PASS: provenance stamping validated"
