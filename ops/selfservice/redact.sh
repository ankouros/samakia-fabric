#!/usr/bin/env bash
set -euo pipefail

redact_text() {
  sed -E 's/(password|token|secret|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH) PRIVATE KEY)/[REDACTED]/gi'
}

redact_file() {
  local src="$1"
  local dest="$2"
  redact_text <"${src}" >"${dest}"
}
