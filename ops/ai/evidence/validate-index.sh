#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

evidence_root="${FABRIC_REPO_ROOT}/evidence/ai"
index_json="${evidence_root}/index.json"
index_md="${evidence_root}/index.md"

if [[ ! -f "${index_json}" || ! -f "${index_md}" ]]; then
  echo "ERROR: AI evidence index missing (run rebuild-index.sh)" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

AI_EVIDENCE_INDEX_OUT="${tmp_dir}" \
  bash "${FABRIC_REPO_ROOT}/ops/ai/evidence/rebuild-index.sh" >/dev/null

if ! cmp -s "${index_json}" "${tmp_dir}/index.json"; then
  echo "ERROR: evidence index JSON is out of date" >&2
  diff -u "${index_json}" "${tmp_dir}/index.json" || true
  exit 1
fi

if ! cmp -s "${index_md}" "${tmp_dir}/index.md"; then
  echo "ERROR: evidence index markdown is out of date" >&2
  diff -u "${index_md}" "${tmp_dir}/index.md" || true
  exit 1
fi

echo "PASS: AI evidence index is deterministic"
