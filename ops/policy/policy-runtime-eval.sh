#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


runtime_dir="${FABRIC_REPO_ROOT}/ops/runtime"

if [[ ! -d "${runtime_dir}" ]]; then
  echo "policy-runtime-eval: missing ops/runtime" >&2
  exit 1
fi

required_files=(
  "ops/runtime/evaluate.sh"
  "ops/runtime/load/signals.sh"
  "ops/runtime/load/slo.sh"
  "ops/runtime/load/observation.sh"
  "ops/runtime/classify/infra.sh"
  "ops/runtime/classify/drift.sh"
  "ops/runtime/classify/slo.sh"
  "ops/runtime/normalize/metrics.sh"
  "ops/runtime/normalize/time.sh"
  "ops/runtime/redact.sh"
  "ops/runtime/evidence.sh"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "${FABRIC_REPO_ROOT}/${file}" ]]; then
    echo "policy-runtime-eval: missing ${file}" >&2
    exit 1
  fi
  if [[ ! -x "${FABRIC_REPO_ROOT}/${file}" ]]; then
    echo "policy-runtime-eval: not executable ${file}" >&2
    exit 1
  fi
done

if ! rg -n "RUNTIME_LIVE" "${FABRIC_REPO_ROOT}/ops/runtime/evaluate.sh" >/dev/null 2>&1; then
  echo "policy-runtime-eval: missing live-mode guard" >&2
  exit 1
fi

if rg -n "(curl|wget|ssh|terraform|ansible-playbook)" "${runtime_dir}" >/dev/null 2>&1; then
  echo "policy-runtime-eval: runtime tooling must be read-only (found network/execution tool)" >&2
  exit 1
fi

if ! rg -n "^evidence/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  echo "policy-runtime-eval: evidence/ not gitignored" >&2
  exit 1
fi

if ! rg -n "^artifacts/" "${FABRIC_REPO_ROOT}/.gitignore" >/dev/null 2>&1; then
  echo "policy-runtime-eval: artifacts/ not gitignored" >&2
  exit 1
fi

echo "policy-runtime-eval: OK"
