#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

if ! command -v rg >/dev/null 2>&1; then
  echo "ERROR: rg not found (required for policy-security checks)" >&2
  exit 1
fi

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: missing required file: ${path}" >&2
    exit 1
  fi
}

require_exec() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: missing or non-executable: ${path}" >&2
    exit 1
  fi
}

# Secrets interface defaults to offline file backend.
if ! rg -n "SECRETS_BACKEND:-file" "${FABRIC_REPO_ROOT}/ops/secrets/secrets.sh" >/dev/null; then
  echo "ERROR: secrets default backend must be file (offline-first)" >&2
  exit 1
fi

require_exec "${FABRIC_REPO_ROOT}/ops/secrets/secrets-file.sh"
require_exec "${FABRIC_REPO_ROOT}/ops/secrets/secrets-vault.sh"

# Firewall apply requires explicit guards.
if ! rg -n "FIREWALL_ENABLE" "${FABRIC_REPO_ROOT}/ops/security/firewall/firewall-apply.sh" >/dev/null; then
  echo "ERROR: firewall apply guard missing (FIREWALL_ENABLE)" >&2
  exit 1
fi
if ! rg -n "FIREWALL_EXECUTE" "${FABRIC_REPO_ROOT}/ops/security/firewall/firewall-apply.sh" >/dev/null; then
  echo "ERROR: firewall apply guard missing (FIREWALL_EXECUTE)" >&2
  exit 1
fi

# SSH rotation guards.
if ! rg -n "ROTATE_EXECUTE" "${FABRIC_REPO_ROOT}/ops/security/ssh/ssh-keys-rotate.sh" >/dev/null; then
  echo "ERROR: ssh rotation guard missing (ROTATE_EXECUTE)" >&2
  exit 1
fi
if ! rg -n "BREAK_GLASS" "${FABRIC_REPO_ROOT}/ops/security/ssh/ssh-keys-rotate.sh" >/dev/null; then
  echo "ERROR: break-glass guard missing (BREAK_GLASS)" >&2
  exit 1
fi
if ! rg -n "I_UNDERSTAND" "${FABRIC_REPO_ROOT}/ops/security/ssh/ssh-keys-rotate.sh" >/dev/null; then
  echo "ERROR: break-glass guard missing (I_UNDERSTAND)" >&2
  exit 1
fi

# Compliance profiles and mapping.
require_file "${FABRIC_REPO_ROOT}/compliance/profiles/baseline.yml"
require_file "${FABRIC_REPO_ROOT}/compliance/profiles/hardened.yml"
require_file "${FABRIC_REPO_ROOT}/compliance/mapping.yml"
require_exec "${FABRIC_REPO_ROOT}/ops/scripts/compliance-eval.sh"

exit 0
