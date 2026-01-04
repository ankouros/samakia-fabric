#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


index_json="${FABRIC_REPO_ROOT}/evidence/index.json"
index_md="${FABRIC_REPO_ROOT}/evidence/INDEX.md"

if [[ ! -f "${index_json}" || ! -f "${index_md}" ]]; then
  echo "ERROR: evidence index missing (run ops/evidence/rebuild-index.sh)" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

EVIDENCE_INDEX_OUT="${tmp_dir}" \
  bash "${FABRIC_REPO_ROOT}/ops/evidence/rebuild-index.sh" >/dev/null

if ! cmp -s "${index_json}" "${tmp_dir}/index.json"; then
  echo "ERROR: evidence index JSON is out of date" >&2
  diff -u "${index_json}" "${tmp_dir}/index.json" || true
  exit 1
fi

if ! cmp -s "${index_md}" "${tmp_dir}/INDEX.md"; then
  echo "ERROR: evidence index markdown is out of date" >&2
  diff -u "${index_md}" "${tmp_dir}/INDEX.md" || true
  exit 1
fi

echo "PASS: evidence index is deterministic"
