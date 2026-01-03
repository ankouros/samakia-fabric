#!/usr/bin/env bash
set -euo pipefail

stamp="${RUNTIME_TIMESTAMP_UTC:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

if [[ -n "${OUT_PATH:-}" ]]; then
  printf '{"timestamp_utc": "%s"}\n' "${stamp}" > "${OUT_PATH}"
else
  echo "${stamp}"
fi
