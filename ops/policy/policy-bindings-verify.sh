#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


verify_dir="${FABRIC_REPO_ROOT}/ops/bindings/verify"
verify_script="${verify_dir}/verify.sh"
probes_dir="${verify_dir}/probes"
common_dir="${verify_dir}/common"

test -x "${verify_script}" || { echo "ERROR: bindings verify runner missing: ${verify_script}" >&2; exit 1; }

required_probes=(
  "tcp_tls.sh"
  "postgres.sh"
  "mariadb.sh"
  "rabbitmq.sh"
  "dragonfly.sh"
  "qdrant.sh"
)

for probe in "${required_probes[@]}"; do
  path="${probes_dir}/${probe}"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: bindings verify probe missing or not executable: ${path}" >&2
    exit 1
  fi
 done

required_common=(
  "json.sh"
  "redact.sh"
  "timeouts.sh"
)

for lib in "${required_common[@]}"; do
  path="${common_dir}/${lib}"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: bindings verify common helper missing or not executable: ${path}" >&2
    exit 1
  fi
 done

if ! rg -q "live mode is not allowed in CI" "${verify_script}"; then
  echo "ERROR: bindings verify must refuse live mode in CI" >&2
  exit 1
fi

if ! rg -q "^evidence/" "${FABRIC_REPO_ROOT}/.gitignore"; then
  echo "ERROR: evidence/ must be gitignored" >&2
  exit 1
fi

if ! rg -q "^artifacts/" "${FABRIC_REPO_ROOT}/.gitignore"; then
  echo "ERROR: artifacts/ must be gitignored" >&2
  exit 1
fi

echo "PASS: bindings verify policy"
