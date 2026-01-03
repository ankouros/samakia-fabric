#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker_part1="${acceptance_dir}/PHASE15_PART1_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase15.part1] ${label}"
  "$@"
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
example_file="${FABRIC_REPO_ROOT}/examples/selfservice/example.yml"

read -r tenant_id proposal_id < <(PROPOSAL_PATH="${example_file}" python3 - <<'PY'
import os
import yaml
from pathlib import Path
proposal = yaml.safe_load(Path(os.environ["PROPOSAL_PATH"]).read_text())
print(proposal.get("tenant_id", ""), proposal.get("proposal_id", ""))
PY
)

if [[ -z "${tenant_id}" || -z "${proposal_id}" ]]; then
  echo "ERROR: example proposal missing tenant_id or proposal_id" >&2
  exit 1
fi

evidence_dir="${FABRIC_REPO_ROOT}/evidence/selfservice/${tenant_id}/${proposal_id}"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check

run_step "Selfservice submit (example)" env SELF_SERVICE_ALLOW_EXISTING=1 FILE="${example_file}" \
  make -C "${FABRIC_REPO_ROOT}" selfservice.submit
run_step "Selfservice validate (example)" make -C "${FABRIC_REPO_ROOT}" selfservice.validate PROPOSAL_ID=example
run_step "Selfservice plan (example)" make -C "${FABRIC_REPO_ROOT}" selfservice.plan PROPOSAL_ID=example
run_step "Selfservice review (example)" make -C "${FABRIC_REPO_ROOT}" selfservice.review PROPOSAL_ID=example
run_step "Phase 15 Part 1 entry check" make -C "${FABRIC_REPO_ROOT}" phase15.part1.entry.check

if PROPOSAL_APPLY=1 make -C "${FABRIC_REPO_ROOT}" selfservice.plan PROPOSAL_ID=example >/dev/null 2>&1; then
  echo "ERROR: selfservice plan allowed execute flags" >&2
  exit 1
fi

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$(${commit_hash_script})"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker_part1}" <<EOF_MARKER
# Phase 15 Part 1 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make selfservice.submit FILE=examples/selfservice/example.yml
- make selfservice.validate PROPOSAL_ID=example
- make selfservice.plan PROPOSAL_ID=example
- make selfservice.review PROPOSAL_ID=example
- make phase15.part1.entry.check
- PROPOSAL_APPLY=1 make selfservice.plan PROPOSAL_ID=example (expected fail)

Result: PASS

Evidence:
- ${evidence_dir}

Statement:
Phase 15 Part 1 enables proposal-only self-service; no tenant can apply changes.
EOF_MARKER

self_hash_part1="$(sha256sum "${marker_part1}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_part1}"
} >>"${marker_part1}"
sha256sum "${marker_part1}" | awk '{print $1}' >"${marker_part1}.sha256"
