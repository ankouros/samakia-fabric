#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
resolver="${repo_root}/ops/scripts/image-next-version.sh"

if [[ ! -x "${resolver}" ]]; then
  fail "resolver script not executable: ${resolver}"
fi

tmp="$(mktemp -d)"
cleanup() { rm -rf "${tmp}"; }
trap cleanup EXIT

mkdir -p "${tmp}"

touch "${tmp}/ubuntu-24.04-lxc-rootfs-v1.tar.gz"
touch "${tmp}/ubuntu-24.04-lxc-rootfs-v2.tar.gz"
touch "${tmp}/ubuntu-24.04-lxc-rootfs-v10.tar.gz"
touch "${tmp}/ubuntu-24.04-lxc-rootfs.tar.gz"
touch "${tmp}/not-a-match-v99.tar.gz"

got="$("${resolver}" --dir "${tmp}")"
[[ "${got}" == "11" ]] || fail "expected next=11 with v1/v2/v10 present, got ${got}"
pass "next=11 when max=10"

rm -f "${tmp}"/ubuntu-24.04-lxc-rootfs-v*.tar.gz
got="$("${resolver}" --dir "${tmp}")"
[[ "${got}" == "1" ]] || fail "expected next=1 when empty, got ${got}"
pass "next=1 when no artifacts present"
