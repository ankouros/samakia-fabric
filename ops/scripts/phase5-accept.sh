#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_cmd date
require_cmd git
require_cmd sha256sum
require_cmd rg

if ! command -v pre-commit >/dev/null 2>&1; then
  echo "ERROR: pre-commit is required for Phase 5 acceptance" >&2
  exit 1
fi

env_file="${RUNNER_ENV_FILE:-${HOME}/.config/samakia-fabric/env.sh}"
if [[ -f "${env_file}" ]]; then
  # shellcheck disable=SC1090
  source "${env_file}"
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"

# Policy gates + standard validation
make -C "${FABRIC_REPO_ROOT}" policy.check
(cd "${FABRIC_REPO_ROOT}" && pre-commit run --all-files)
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"

# Compliance evaluations (baseline + hardened)
bash "${FABRIC_REPO_ROOT}/ops/scripts/compliance-eval.sh" --profile baseline
bash "${FABRIC_REPO_ROOT}/ops/scripts/compliance-eval.sh" --profile hardened

# Firewall default-off + profile integrity
bash "${FABRIC_REPO_ROOT}/ops/security/firewall/firewall-check.sh"

# SSH rotation dry-run (local/offline)
SSH_DRYRUN_MODE=local bash "${FABRIC_REPO_ROOT}/ops/security/ssh/ssh-keys-dryrun.sh"

# Secrets interface doctor
bash "${FABRIC_REPO_ROOT}/ops/secrets/secrets.sh" doctor

commit_full="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"

marker_tmp="$(mktemp)"
cat >"${marker_tmp}" <<'MARKER_EOF'
# Phase 5 Acceptance Marker — Advanced Security & Compliance

Phase: Phase 5 — Advanced Security & Compliance
Scope source: ROADMAP.md (Phase 5)

Acceptance statement:
Phase 5 is ACCEPTED and LOCKED. Any further changes are regressions.

Repository:
- Commit: COMMIT_PLACEHOLDER
- Timestamp (UTC): TIMESTAMP_PLACEHOLDER

Acceptance commands executed:
- make policy.check
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- compliance-eval.sh --profile baseline
- compliance-eval.sh --profile hardened
- firewall-check.sh
- SSH_DRYRUN_MODE=local ssh-keys-dryrun.sh
- secrets.sh doctor

PASS summary:
- Policy gates: PASS
- Compliance eval baseline: PASS
- Compliance eval hardened: PASS (NA allowed per mapping)
- Firewall checks: PASS
- SSH rotation dry-run: PASS
- Secrets interface doctor: PASS
MARKER_EOF

sed -i "s/COMMIT_PLACEHOLDER/${commit_full}/" "${marker_tmp}"
sed -i "s/TIMESTAMP_PLACEHOLDER/${stamp}/" "${marker_tmp}"

hash="$(sha256sum "${marker_tmp}" | awk '{print $1}')"
marker="${FABRIC_REPO_ROOT}/acceptance/PHASE5_ACCEPTED.md"
cat "${marker_tmp}" >"${marker}"
echo "SHA256 (content excluding this line): ${hash}" >>"${marker}"
rm -f "${marker_tmp}" 2>/dev/null || true

echo "OK: wrote ${marker}"
