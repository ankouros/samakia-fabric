#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export FABRIC_REPO_ROOT="${ROOT_DIR}"

src_json="${ROOT_DIR}/hardening/checklist.json"
if [[ ! -f "${src_json}" ]]; then
  echo "ERROR: missing hardening checklist: ${src_json}" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

render_doc="${tmp_dir}/hardening.md"
render_entry="${tmp_dir}/PHASE11_HARDENING_ENTRY_CHECKLIST.md"

bash "${ROOT_DIR}/hardening/render/checklist-to-md.sh" \
  --input "${src_json}" \
  --doc-output "${render_doc}" \
  --entry-output "${render_entry}"

if ! cmp -s "${render_doc}" "${ROOT_DIR}/docs/operator/hardening.md"; then
  echo "ERROR: docs/operator/hardening.md does not match generated output" >&2
  exit 1
fi

if ! cmp -s "${render_entry}" "${ROOT_DIR}/acceptance/PHASE11_HARDENING_ENTRY_CHECKLIST.md"; then
  echo "ERROR: acceptance/PHASE11_HARDENING_ENTRY_CHECKLIST.md does not match generated output" >&2
  exit 1
fi

echo "PASS: auto-generated docs are in sync"
