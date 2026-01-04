#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

backend="${BIND_SECRETS_BACKEND:-${SECRETS_BACKEND:-vault}}"

skip() {
  echo "SKIP: ${1}"
  exit 0
}

case "${backend}" in
  vault)
    if [[ -z "${VAULT_ADDR:-}" || -z "${VAULT_TOKEN:-}" ]]; then
      skip "Vault backend not configured (set VAULT_ADDR/VAULT_TOKEN to enforce non-empty secrets)."
    fi
    ;;
  file)
    if [[ -z "${SECRETS_PASSPHRASE:-}" && -z "${SECRETS_PASSPHRASE_FILE:-}" ]]; then
      skip "File backend passphrase not configured (set SECRETS_PASSPHRASE or SECRETS_PASSPHRASE_FILE)."
    fi
    ;;
  *)
    echo "ERROR: unsupported secrets backend: ${backend}" >&2
    exit 2
    ;;
esac

validate_script="${FABRIC_REPO_ROOT}/ops/secrets/validate-secret.sh"
if [[ ! -x "${validate_script}" ]]; then
  echo "ERROR: validate-secret helper missing or not executable: ${validate_script}" >&2
  exit 1
fi

bindings_root="${FABRIC_REPO_ROOT}/contracts/bindings/tenants"
if [[ ! -d "${bindings_root}" ]]; then
  echo "ERROR: bindings directory not found: ${bindings_root}" >&2
  exit 1
fi

mapfile -t entries < <(python3 - "${bindings_root}" <<'PY'
import sys
from pathlib import Path
import yaml

root = Path(sys.argv[1])
entries = []
for path in sorted(root.glob("**/*.binding.yml")):
    data = yaml.safe_load(path.read_text()) or {}
    consumers = data.get("spec", {}).get("consumers", [])
    for consumer in consumers:
        provider = consumer.get("provider")
        secret_ref = consumer.get("secret_ref")
        if provider and secret_ref:
            entries.append((provider, secret_ref, str(path)))

for provider, secret_ref, path in entries:
    print(f"{provider}|{secret_ref}|{path}")
PY
)

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "PASS: no binding secrets to validate"
  exit 0
fi

declare -A required_fields
required_fields["postgres"]="username password"
required_fields["mariadb"]="username password"
required_fields["rabbitmq"]="username password"

for entry in "${entries[@]}"; do
  provider="${entry%%|*}"
  rest="${entry#*|}"
  secret_ref="${rest%%|*}"
  binding_path="${rest#*|}"

  fields="${required_fields[${provider}]:-}"
  if [[ -z "${fields}" ]]; then
    continue
  fi

  args=()
  for field in ${fields}; do
    args+=(--require "${field}")
  done

  if ! SECRETS_BACKEND="${backend}" "${validate_script}" "${secret_ref}" "${args[@]}"; then
    echo "ERROR: non-empty secret validation failed for ${binding_path}" >&2
    exit 1
  fi
done

echo "PASS: non-empty secret validation completed"
