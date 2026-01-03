#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


backend="${BIND_SECRETS_BACKEND:-vault}"
backend_script="${FABRIC_REPO_ROOT}/ops/bindings/secrets/backends/${backend}.sh"

if [[ ! -x "${backend_script}" ]]; then
  echo "ERROR: secrets backend not found or not executable: ${backend_script}" >&2
  exit 2
fi

bindings_root="${FABRIC_REPO_ROOT}/contracts/bindings/tenants"
mapfile -t bindings < <(find "${bindings_root}" -type f -name "*.binding.yml" -print | sort)
if [[ ${#bindings[@]} -eq 0 ]]; then
  echo "ERROR: no binding contracts found under ${bindings_root}" >&2
  exit 1
fi

refs=$(BINDINGS_LIST="$(printf '%s\n' "${bindings[@]}")" python3 - <<'PY'
import os
from pathlib import Path
import yaml

bindings = [Path(p) for p in os.environ.get("BINDINGS_LIST", "").splitlines() if p]
entries = []

for binding in bindings:
    data = yaml.safe_load(binding.read_text())
    meta = data.get("metadata", {})
    tenant = meta.get("tenant") or ""
    env = meta.get("env") or ""
    for consumer in data.get("spec", {}).get("consumers", []):
        secret_ref = consumer.get("secret_ref") or ""
        secret_shape = consumer.get("secret_shape") or ""
        entries.append((tenant, env, secret_ref, secret_shape))

for tenant, env, secret_ref, secret_shape in entries:
    print(f"{tenant}\t{env}\t{secret_ref}\t{secret_shape}")
PY
)

if [[ -z "${refs}" ]]; then
  echo "ERROR: no secret refs found in bindings" >&2
  exit 1
fi

missing=0
while IFS=$'\t' read -r tenant env secret_ref secret_shape; do
  if [[ -z "${secret_ref}" ]]; then
    echo "FAIL secrets: ${tenant}/${env}: secret_ref missing" >&2
    missing=1
    continue
  fi
  if "${backend_script}" get "${secret_ref}" >/dev/null 2>&1; then
    echo "PASS secrets: ${tenant}/${env} ${secret_ref} (${secret_shape})"
  else
    echo "WARN secrets: ${tenant}/${env} ${secret_ref} (${secret_shape}) missing"
    missing=1
  fi
done <<< "${refs}"

if [[ "${missing}" -ne 0 ]]; then
  if [[ "${BIND_SECRETS_STRICT:-0}" == "1" ]]; then
    echo "ERROR: one or more secret refs missing (BIND_SECRETS_STRICT=1)" >&2
    exit 1
  fi
  echo "WARN: one or more secret refs missing (set BIND_SECRETS_STRICT=1 to fail)" >&2
fi
