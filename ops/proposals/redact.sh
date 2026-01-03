#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


redact_text() {
  sed -E 's/(password|token|secret|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH) PRIVATE KEY)/[REDACTED]/gi'
}

redact_file() {
  local src="$1"
  local dest="$2"
  redact_text <"${src}" >"${dest}"
}
