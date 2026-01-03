#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE11_HARDENING_JSON_ACCEPTED.md"
marker_hash="${marker}.sha256"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

evidence_dir="${FABRIC_REPO_ROOT}/evidence/hardening/${stamp}"
manifest_path="${evidence_dir}/manifest.sha256"

run_step() {
  local label="$1"
  shift
  echo "[phase11.hardening] ${label}"
  "$@"
}

commands=(
  "pre-commit run --all-files"
  "bash fabric-ci/scripts/lint.sh"
  "bash fabric-ci/scripts/validate.sh"
  "make policy.check"
  "make docs.operator.check"
  "make tenants.validate"
  "make substrate.contracts.validate"
  "make tenants.capacity.validate TENANT=all"
  "make substrate.observe TENANT=all"
  "make substrate.observe.compare TENANT=all"
  "make hardening.checklist.validate"
  "make hardening.checklist.render"
  "make hardening.checklist.summary"
  "make phase11.hardening.entry.check"
)

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Operator docs check" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "Tenant validation" make -C "${FABRIC_REPO_ROOT}" tenants.validate
run_step "Substrate contract validation" make -C "${FABRIC_REPO_ROOT}" substrate.contracts.validate
run_step "Capacity validation" make -C "${FABRIC_REPO_ROOT}" tenants.capacity.validate TENANT=all
run_step "Substrate observe" make -C "${FABRIC_REPO_ROOT}" substrate.observe TENANT=all
run_step "Substrate observe compare" make -C "${FABRIC_REPO_ROOT}" substrate.observe.compare TENANT=all
run_step "Hardening checklist validate" make -C "${FABRIC_REPO_ROOT}" hardening.checklist.validate
run_step "Hardening checklist render" make -C "${FABRIC_REPO_ROOT}" hardening.checklist.render
run_step "Hardening checklist summary" make -C "${FABRIC_REPO_ROOT}" hardening.checklist.summary
run_step "Hardening entry check" make -C "${FABRIC_REPO_ROOT}" phase11.hardening.entry.check

mkdir -p "${evidence_dir}"
commit_hash="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
commit_hash="$(${commit_hash} 2>/dev/null || git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"

COMMANDS_PAYLOAD=$(printf '%s\n' "${commands[@]}")
(
  cd "${evidence_dir}"
  COMMANDS="${COMMANDS_PAYLOAD}" COMMIT_HASH="${commit_hash}" STAMP="${stamp}" python3 - <<'PY'
import json
import os
from pathlib import Path

commands = [line for line in os.environ.get("COMMANDS", "").splitlines() if line]
commit_hash = os.environ["COMMIT_HASH"]
stamp = os.environ["STAMP"]

Path("summary.md").write_text(
    "# Phase 11 Pre-Exposure Hardening Gate Evidence\n\n"
    f"Timestamp (UTC): {stamp}\n"
    f"Commit: {commit_hash}\n\n"
    "Commands executed:\n"
    + "\n".join([f"- {cmd}" for cmd in commands])
    + "\n\nResult: PASS\n"
)

checks = [{"command": cmd, "result": "PASS"} for cmd in commands]
Path("checks.json").write_text(json.dumps(checks, indent=2, sort_keys=True) + "\n")
PY
)

(
  cd "${evidence_dir}"
  printf "summary.md\nchecks.json\n" | while read -r file; do
    sha256sum "${file}"
  done > "${manifest_path}"
)

if [[ "${EVIDENCE_SIGN:-0}" == "1" ]]; then
  if [[ -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
    echo "ERROR: EVIDENCE_SIGN=1 but EVIDENCE_SIGN_KEY is not set" >&2
    exit 1
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg not found; cannot sign evidence" >&2
    exit 1
  fi
  gpg --batch --yes --local-user "${EVIDENCE_SIGN_KEY}" \
    --armor --detach-sign "${manifest_path}"
fi

mkdir -p "${acceptance_dir}"
cat >"${marker}" <<EOF_MARKER
# Phase 11 Pre-Exposure Hardening Gate Acceptance (JSON Checklist)

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- make tenants.validate
- make substrate.contracts.validate
- make tenants.capacity.validate TENANT=all
- make substrate.observe TENANT=all
- make substrate.observe.compare TENANT=all
- make hardening.checklist.validate
- make hardening.checklist.render
- make hardening.checklist.summary
- make phase11.hardening.entry.check

Result: PASS

Evidence:
- ${evidence_dir}/summary.md
- ${evidence_dir}/checks.json

Statement:
Phase 11 pre-exposure hardening gate passed. Checklist is machine-verifiable and auto-generated.
EOF_MARKER

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >> "${marker}"
sha256sum "${marker}" | awk '{print $1}' > "${marker_hash}"
