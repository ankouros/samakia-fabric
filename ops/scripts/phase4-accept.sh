#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

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
require_cmd find
require_cmd sort
require_cmd xargs
require_cmd rg
require_cmd awk
require_cmd sed

if ! command -v pre-commit >/dev/null 2>&1; then
  echo "ERROR: pre-commit is required for Phase 4 acceptance" >&2
  exit 1
fi

env_file="${RUNNER_ENV_FILE:-${HOME}/.config/samakia-fabric/env.sh}"
if [[ -f "${env_file}" ]]; then
  # shellcheck disable=SC1090
  source "${env_file}"
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"

verify_manifest() {
  local target_dir="$1"
  local manifest_path="${target_dir}/manifest.sha256"
  local tmp_manifest
  if [[ ! -f "${manifest_path}" ]]; then
    echo "ERROR: manifest missing: ${manifest_path}" >&2
    exit 1
  fi
  tmp_manifest="$(mktemp)"
  (
    cd "${target_dir}"
    find . \
      -type f \
      ! -name 'manifest.sha256' \
      ! -name 'manifest.sha256.asc' \
      ! -name 'manifest.sha256.asc.a' \
      ! -name 'manifest.sha256.asc.b' \
      ! -name 'manifest.sha256.tsr' \
      -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 sha256sum >"${tmp_manifest}"
  )
  if ! diff -q "${manifest_path}" "${tmp_manifest}" >/dev/null 2>&1; then
    echo "ERROR: manifest is not deterministic for ${target_dir}" >&2
    rm -f "${tmp_manifest}" 2>/dev/null || true
    exit 1
  fi
  rm -f "${tmp_manifest}" 2>/dev/null || true
}

check_redaction() {
  local file_path="$1"
  if rg -n "AWS_SECRET_ACCESS_KEY|TF_VAR_pm_api_token_secret|PM_API_TOKEN_SECRET" "${file_path}" >/dev/null 2>&1; then
    echo "ERROR: secret-like tokens detected in ${file_path}" >&2
    exit 1
  fi
}

# Policy gates
make -C "${FABRIC_REPO_ROOT}" policy.check

# CI-equivalent validation
(cd "${FABRIC_REPO_ROOT}" && pre-commit run --all-files)
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"

sample_root="${FABRIC_REPO_ROOT}/tmp/phase4-accept-${stamp}"
mkdir -p "${sample_root}"

# Sample drift packet (offline)
drift_dir="${sample_root}/drift"
DRIFT_OUT_DIR="${drift_dir}" bash "${FABRIC_REPO_ROOT}/ops/scripts/drift-packet.sh" sample --sample --out-dir "${drift_dir}"
verify_manifest "${drift_dir}"
check_redaction "${drift_dir}/terraform-plan.txt"
check_redaction "${drift_dir}/ansible-check.txt"

# Sample app compliance packet
sample_cfg_dir="${sample_root}/service"
mkdir -p "${sample_cfg_dir}"
config_path="${sample_cfg_dir}/config.txt"
config_list="${sample_cfg_dir}/paths.txt"

printf 'sample=true\n' >"${config_path}"
rel_path="${config_path#"${FABRIC_REPO_ROOT}"/}"
printf '%s\n' "${rel_path}" >"${config_list}"

app_output="$("${FABRIC_REPO_ROOT}"/ops/scripts/app-compliance-packet.sh sample sample "${FABRIC_REPO_ROOT}" --config "${config_list}" --version "phase4-sample" 2>&1)"
app_packet_dir="$(printf '%s\n' "${app_output}" | awk -F': ' '/^OK: wrote application evidence bundle:/{print $3; exit}')"
if [[ -z "${app_packet_dir}" ]]; then
  echo "ERROR: app compliance packet did not report output directory" >&2
  printf '%s\n' "${app_output}" >&2
  exit 1
fi
verify_manifest "${app_packet_dir}"

# Sample release readiness packet
release_id="phase4-sample-${stamp}"
ALLOW_DIRTY_GIT=1 bash "${FABRIC_REPO_ROOT}/ops/scripts/release-readiness-packet.sh" "${release_id}" sample
release_dir="${FABRIC_REPO_ROOT}/release-readiness/${release_id}"
verify_manifest "${release_dir}"

# Apply workflow gating (static checks)
apply_wf="${FABRIC_REPO_ROOT}/.github/workflows/apply-nonprod.yml"
if ! rg -n "I_UNDERSTAND_APPLY_IS_MUTATING" "${apply_wf}" >/dev/null 2>&1; then
  echo "ERROR: apply workflow confirmation phrase missing" >&2
  exit 1
fi
if ! rg -n "samakia-dev" "${apply_wf}" >/dev/null 2>&1 || ! rg -n "samakia-staging" "${apply_wf}" >/dev/null 2>&1; then
  echo "ERROR: apply workflow env allowlist incomplete" >&2
  exit 1
fi
if rg -n "samakia-prod" "${apply_wf}" >/dev/null 2>&1; then
  echo "ERROR: apply workflow must not allow prod" >&2
  exit 1
fi

commit_full="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"

marker_tmp="$(mktemp)"
cat >"${marker_tmp}" <<'MARKER_EOF'
# Phase 4 Acceptance Marker — GitOps & CI/CD Integration

Phase: Phase 4 — GitOps & CI/CD Integration
Scope source: ROADMAP.md (Phase 4)

Acceptance statement:
Phase 4 is ACCEPTED and LOCKED. Any further changes are regressions.

Repository:
- Commit: COMMIT_PLACEHOLDER
- Timestamp (UTC): TIMESTAMP_PLACEHOLDER

Acceptance commands executed:
- make policy.check
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- drift-packet.sh sample --sample
- app-compliance-packet.sh sample sample <repo>
- release-readiness-packet.sh RELEASE_PLACEHOLDER sample
- static workflow gating checks

PASS summary:
- Policy gates: PASS
- CI-equivalent validation: PASS
- Drift packet manifest + redaction: PASS
- App compliance packet manifest: PASS
- Release readiness packet manifest: PASS
- Apply workflow gating: PASS
MARKER_EOF

sed -i "s/COMMIT_PLACEHOLDER/${commit_full}/" "${marker_tmp}"
sed -i "s/TIMESTAMP_PLACEHOLDER/${stamp}/" "${marker_tmp}"
sed -i "s/RELEASE_PLACEHOLDER/${release_id}/" "${marker_tmp}"

hash="$(sha256sum "${marker_tmp}" | awk '{print $1}')"
marker="${FABRIC_REPO_ROOT}/acceptance/PHASE4_ACCEPTED.md"
cat "${marker_tmp}" >"${marker}"
echo "SHA256 (content excluding this line): ${hash}" >>"${marker}"
rm -f "${marker_tmp}" 2>/dev/null || true

echo "OK: wrote ${marker}"
