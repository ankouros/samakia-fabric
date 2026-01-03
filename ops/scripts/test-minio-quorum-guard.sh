#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FABRIC_REPO_ROOT="$(cd "${script_dir}/../.." && pwd)"
export FABRIC_REPO_ROOT

# shellcheck disable=SC1090
source "${FABRIC_REPO_ROOT}/ops/scripts/minio-quorum-guard.sh"

got="$(minio_guard_evaluate_signals 1 1 1 1 1 1 1 || true)"
[[ "${got}" == "PASS" ]] || fail "expected PASS, got ${got}"
pass "PASS when all required signals OK"

got="$(minio_guard_evaluate_signals 0 1 1 1 1 1 1 || true)"
[[ "${got}" == "FAIL" ]] || fail "expected FAIL on vip_tls_ok=0, got ${got}"
pass "FAIL when VIP TLS is not OK"

got="$(minio_guard_evaluate_signals 1 0 1 1 1 1 1 || true)"
[[ "${got}" == "FAIL" ]] || fail "expected FAIL on edge_ha_ok=0, got ${got}"
pass "FAIL when edge HA is not OK"

got="$(minio_guard_evaluate_signals 1 1 1 1 1 0 1 || true)"
[[ "${got}" == "WARN" ]] || fail "expected WARN when backends_ok=0, got ${got}"
pass "WARN when backends are degraded but hard prerequisites OK"

got="$(minio_guard_evaluate_signals 1 1 1 1 1 1 0 || true)"
[[ "${got}" == "WARN" ]] || fail "expected WARN when admin_ok=0, got ${got}"
pass "WARN when admin health signals are missing/degraded"
