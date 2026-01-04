#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

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

cutover_plan="${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-plan.sh"
cutover_apply="${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-apply.sh"
cutover_rollback="${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-rollback.sh"
cutover_validate="${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-validate.sh"
cutover_evidence="${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-evidence.sh"
cutover_redact="${FABRIC_REPO_ROOT}/ops/bindings/rotate/redact.sh"
cutover_schema="${FABRIC_REPO_ROOT}/contracts/rotation/cutover.schema.json"

require_exec "${cutover_plan}"
require_exec "${cutover_apply}"
require_exec "${cutover_rollback}"
require_exec "${cutover_validate}"
require_exec "${cutover_evidence}"
require_exec "${cutover_redact}"

if [[ ! -f "${cutover_schema}" ]]; then
  echo "ERROR: cutover schema missing: ${cutover_schema}" >&2
  exit 1
fi

if ! rg -n "ROTATE_EXECUTE" "${cutover_apply}" >/dev/null; then
  echo "ERROR: cutover apply guard missing (ROTATE_EXECUTE)" >&2
  exit 1
fi

if ! rg -n "CUTOVER_EXECUTE" "${cutover_apply}" >/dev/null; then
  echo "ERROR: cutover apply guard missing (CUTOVER_EXECUTE)" >&2
  exit 1
fi

if ! rg -n "ROTATE_REASON" "${cutover_apply}" >/dev/null; then
  echo "ERROR: cutover apply guard missing (ROTATE_REASON)" >&2
  exit 1
fi

if ! rg -n "ROLLBACK_EXECUTE" "${cutover_rollback}" >/dev/null; then
  echo "ERROR: cutover rollback guard missing (ROLLBACK_EXECUTE)" >&2
  exit 1
fi

if ! rg -n "ROTATE_REASON" "${cutover_rollback}" >/dev/null; then
  echo "ERROR: cutover rollback guard missing (ROTATE_REASON)" >&2
  exit 1
fi

if ! rg -n "not allowed in CI" "${cutover_apply}" >/dev/null; then
  echo "ERROR: cutover apply must refuse CI" >&2
  exit 1
fi

if ! rg -n "not allowed in CI" "${cutover_rollback}" >/dev/null; then
  echo "ERROR: cutover rollback must refuse CI" >&2
  exit 1
fi

if ! rg -n "change-window.sh" "${cutover_apply}" >/dev/null; then
  echo "ERROR: prod cutover apply must enforce change window" >&2
  exit 1
fi

if ! rg -n "change-window.sh" "${cutover_rollback}" >/dev/null; then
  echo "ERROR: prod cutover rollback must enforce change window" >&2
  exit 1
fi

if ! rg -n "EVIDENCE_SIGN" "${cutover_apply}" >/dev/null; then
  echo "ERROR: prod cutover apply must enforce evidence signing" >&2
  exit 1
fi

if ! rg -n "EVIDENCE_SIGN" "${cutover_rollback}" >/dev/null; then
  echo "ERROR: prod cutover rollback must enforce evidence signing" >&2
  exit 1
fi

if ! rg -n "backup" "${cutover_rollback}" >/dev/null; then
  echo "ERROR: cutover rollback must restore from backup" >&2
  exit 1
fi

if rg -n "(password|token|api_key|access_key|private_key|secret_value)\s*:" "${FABRIC_REPO_ROOT}/contracts/rotation" >/dev/null 2>&1; then
  echo "ERROR: cutover contracts must not include secret values" >&2
  exit 1
fi

exit 0
