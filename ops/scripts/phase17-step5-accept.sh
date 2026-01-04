#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE17_STEP5_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase17.step5] ${label}"
  "$@"
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
example_file="${FABRIC_REPO_ROOT}/contracts/rotation/examples/cutover-nonprod.yml"

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

secrets_file="${work_dir}/secrets.enc"
passphrase="ci-cutover-passphrase"

seed_secret() {
  local ref="$1"
  cat <<'PAYLOAD' | SECRETS_FILE="${secrets_file}" SECRETS_PASSPHRASE="${passphrase}" \
    bash "${FABRIC_REPO_ROOT}/ops/bindings/secrets/backends/file.sh" put "${ref}" -
{"database":"birds","host":"db.canary.internal","password":"ci-placeholder","port":"5432","sslmode":"verify-full","username":"canary_app"}
PAYLOAD
}

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" env -u CI bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Phase 17 Step 5 entry check" make -C "${FABRIC_REPO_ROOT}" phase17.step5.entry.check

seed_secret "tenants/canary/database/sample"
seed_secret "tenants/canary/database/sample-v2"

run_step "Cutover plan (example)" env \
  BIND_SECRETS_BACKEND="file" SECRETS_FILE="${secrets_file}" SECRETS_PASSPHRASE="${passphrase}" \
  make -C "${FABRIC_REPO_ROOT}" rotation.cutover.plan FILE="${example_file}"

run_step "Cutover validate (example)" env \
  BIND_SECRETS_BACKEND="file" SECRETS_FILE="${secrets_file}" SECRETS_PASSPHRASE="${passphrase}" \
  bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-validate.sh" --file "${example_file}"

if BIND_SECRETS_BACKEND="file" SECRETS_FILE="${secrets_file}" SECRETS_PASSPHRASE="${passphrase}" \
  bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/cutover-apply.sh" --file "${example_file}" >/dev/null 2>&1; then
  echo "ERROR: cutover apply should refuse without guards" >&2
  exit 1
else
  echo "PASS: cutover apply refused without guards"
fi

if CI=1 VERIFY_MODE=live VERIFY_LIVE=1 TENANT=canary WORKLOAD=sample \
  BIND_SECRETS_BACKEND="file" SECRETS_FILE="${secrets_file}" SECRETS_PASSPHRASE="${passphrase}" \
  bash "${FABRIC_REPO_ROOT}/ops/bindings/verify/verify.sh" >/dev/null 2>&1; then
  echo "ERROR: live verify should be blocked in CI" >&2
  exit 1
else
  echo "PASS: live verify refused in CI"
fi

run_step "Roadmap updated" rg -n "Step 5" "${FABRIC_REPO_ROOT}/ROADMAP.md"
run_step "Changelog updated" rg -n "Step 5" "${FABRIC_REPO_ROOT}/CHANGELOG.md"
run_step "Review updated" rg -n "Step 5" "${FABRIC_REPO_ROOT}/REVIEW.md"
run_step "Operations updated" rg -n "cutover" "${FABRIC_REPO_ROOT}/OPERATIONS.md"

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$(${commit_hash_script})"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker}" <<EOF_MARKER
# Phase 17 Step 5 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make phase17.step5.entry.check
- make rotation.cutover.plan FILE=contracts/rotation/examples/cutover-nonprod.yml
- ops/bindings/rotate/cutover-validate.sh --file contracts/rotation/examples/cutover-nonprod.yml
- cutover apply guard refusal check
- CI live verify refusal check
- rg -n "Step 5" ROADMAP.md
- rg -n "Step 5" CHANGELOG.md
- rg -n "Step 5" REVIEW.md
- rg -n "cutover" OPERATIONS.md

Result: PASS

Statement:
Secrets rotation cutover is operator-controlled, reversible, and evidence-backed.
No secrets are written to Git or evidence. CI remains read-only.
EOF_MARKER

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >>"${marker}"
sha256sum "${marker}" | awk '{print $1}' >"${marker}.sha256"
