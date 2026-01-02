#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VERIFY_SCRIPT="${ROOT_DIR}/ops/milestones/phase1-12/verify.sh"

if [[ ! -x "${VERIFY_SCRIPT}" ]]; then
  echo "ERROR: milestone verifier not executable: ${VERIFY_SCRIPT}" >&2
  exit 1
fi

tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_root}" 2>/dev/null || true
}
trap cleanup EXIT

export FABRIC_REPO_ROOT="${ROOT_DIR}"
export MILESTONE_PACKET_ROOT="${tmp_root}"
export MILESTONE_STAMP="wrapper-exit-test"
export MILESTONE_TEST_MODE=1
export MILESTONE_TEST_FAIL=1

set +e
bash "${VERIFY_SCRIPT}"
rc=$?
set -e

if [[ ${rc} -eq 0 ]]; then
  echo "ERROR: expected non-zero exit from milestone wrapper test" >&2
  exit 1
fi

if [[ ${rc} -ne 23 ]]; then
  echo "ERROR: expected exit code 23, got ${rc}" >&2
  exit 1
fi

step_dir="${tmp_root}/${MILESTONE_STAMP}/steps/test-fail"
stdout_log="${step_dir}/stdout.log"
stderr_log="${step_dir}/stderr.log"
exit_code_file="${step_dir}/exit_code"

for path in "${stdout_log}" "${stderr_log}" "${exit_code_file}"; do
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: missing evidence log: ${path}" >&2
    exit 1
  fi
done

if ! grep -q "23" "${exit_code_file}"; then
  echo "ERROR: expected exit_code to contain 23" >&2
  exit 1
fi

if ! grep -q "intentional failure" "${stderr_log}"; then
  echo "ERROR: expected stderr to include failure marker" >&2
  exit 1
fi

echo "PASS: milestone wrapper exit semantics and logs preserved"
