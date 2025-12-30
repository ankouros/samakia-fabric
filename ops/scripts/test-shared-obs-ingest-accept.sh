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
source "${FABRIC_REPO_ROOT}/ops/scripts/shared-obs-ingest-accept.sh"

tmp_ok="$(mktemp)"
tmp_empty="$(mktemp)"

cat >"${tmp_ok}" <<'JSON'
{"status":"success","data":[{"stream":{"job":"systemd-journal"},"values":[["1","msg"]]}]}
JSON

cat >"${tmp_empty}" <<'JSON'
{"status":"success","data":[]}
JSON

count_ok="$(obs_ingest_series_count "${tmp_ok}")"
count_empty="$(obs_ingest_series_count "${tmp_empty}")"

rm -f "${tmp_ok}" "${tmp_empty}"

[[ "${count_ok}" -eq 1 ]] || fail "expected series count 1, got ${count_ok}"
pass "series count parses non-empty payload"

[[ "${count_empty}" -eq 0 ]] || fail "expected series count 0, got ${count_empty}"
pass "series count parses empty payload"
