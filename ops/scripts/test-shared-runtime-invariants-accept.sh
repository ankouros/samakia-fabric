#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2317
pass() { echo "PASS: $*"; }
# shellcheck disable=SC2317
fail() { echo "FAIL: $*" >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FABRIC_REPO_ROOT="$(cd "${script_dir}/../.." && pwd)"
export FABRIC_REPO_ROOT

# shellcheck disable=SC1090
source "${FABRIC_REPO_ROOT}/ops/scripts/shared-runtime-invariants-accept.sh"

got="$(runtime_invariants_eval 1 1 1 || true)"
[[ "${got}" == "PASS" ]] || fail "expected PASS, got ${got}"
pass "PASS when active/enabled/restart are OK"

got="$(runtime_invariants_eval 0 1 1 || true)"
[[ "${got}" == "FAIL" ]] || fail "expected FAIL on active=0, got ${got}"
pass "FAIL when active is not OK"

got="$(runtime_invariants_eval 1 0 1 || true)"
[[ "${got}" == "FAIL" ]] || fail "expected FAIL on enabled=0, got ${got}"
pass "FAIL when enabled is not OK"

got="$(runtime_invariants_eval 1 1 0 || true)"
[[ "${got}" == "FAIL" ]] || fail "expected FAIL on restart=0, got ${got}"
pass "FAIL when restart policy is not OK"
