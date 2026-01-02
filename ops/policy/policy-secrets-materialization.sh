#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR: rg not found (required for policy checks)" >&2
  exit 1
fi

require_exec() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: missing or non-executable: ${path}" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: missing required file: ${path}" >&2
    exit 1
  fi
}

materialize="${FABRIC_REPO_ROOT}/ops/bindings/secrets/materialize.sh"
inspect="${FABRIC_REPO_ROOT}/ops/bindings/secrets/inspect.sh"
generate="${FABRIC_REPO_ROOT}/ops/bindings/secrets/generate.sh"
file_backend="${FABRIC_REPO_ROOT}/ops/bindings/secrets/backends/file.sh"
vault_backend="${FABRIC_REPO_ROOT}/ops/bindings/secrets/backends/vault.sh"

require_file "${FABRIC_REPO_ROOT}/docs/bindings/secrets.md"
require_exec "${materialize}"
require_exec "${inspect}"
require_exec "${generate}"
require_exec "${file_backend}"
require_exec "${vault_backend}"

if ! rg -n "MATERIALIZE_EXECUTE" "${materialize}" >/dev/null; then
  echo "ERROR: materialize guard missing (MATERIALIZE_EXECUTE)" >&2
  exit 1
fi

if ! rg -n "BIND_SECRETS_BACKEND:-file" "${materialize}" >/dev/null; then
  echo "ERROR: materialize default backend must be file" >&2
  exit 1
fi

if ! rg -n "change-window.sh" "${materialize}" >/dev/null; then
  echo "ERROR: materialize must enforce change window for prod" >&2
  exit 1
fi

if ! rg -n "evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null; then
  echo "ERROR: evidence paths must be gitignored" >&2
  exit 1
fi

exit 0
