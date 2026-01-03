#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker_part2="${acceptance_dir}/PHASE16_PART2_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase16.part2] ${label}"
  "$@"
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "AI indexing doctor" make -C "${FABRIC_REPO_ROOT}" ai.index.doctor
run_step "AI indexing offline" make -C "${FABRIC_REPO_ROOT}" ai.index.offline TENANT=platform SOURCE=docs
run_step "Phase 16 Part 2 entry check" make -C "${FABRIC_REPO_ROOT}" phase16.part2.entry.check

index_root="${FABRIC_REPO_ROOT}/evidence/ai/indexing/platform"
if [[ ! -d "${index_root}" ]]; then
  echo "ERROR: indexing evidence not found: ${index_root}" >&2
  exit 1
fi

latest_dir="$(find "${index_root}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort | tail -n1)"
if [[ -z "${latest_dir}" ]]; then
  echo "ERROR: no indexing evidence directories found in ${index_root}" >&2
  exit 1
fi
evidence_dir="${index_root}/${latest_dir}"

if [[ ! -f "${evidence_dir}/redaction.json" ]]; then
  echo "ERROR: redaction.json missing in ${evidence_dir}" >&2
  exit 1
fi

if [[ ! -f "${evidence_dir}/embedding.json" ]]; then
  echo "ERROR: embedding.json missing in ${evidence_dir}" >&2
  exit 1
fi

if [[ ! -f "${evidence_dir}/qdrant.json" ]]; then
  echo "ERROR: qdrant.json missing in ${evidence_dir}" >&2
  exit 1
fi

EVIDENCE_DIR="${evidence_dir}" python3 - <<'PY'
import json
import os
from pathlib import Path

evidence_dir = Path(os.environ["EVIDENCE_DIR"])

redaction = json.loads((evidence_dir / "redaction.json").read_text(encoding="utf-8"))
embedding = json.loads((evidence_dir / "embedding.json").read_text(encoding="utf-8"))
qdrant = json.loads((evidence_dir / "qdrant.json").read_text(encoding="utf-8"))

redactions = redaction.get("redactions", [])
if not redactions:
    raise SystemExit("ERROR: redaction did not deny any fixture content")

if not any("TEST_ONLY_SECRET" in match for item in redactions for match in item.get("matches", [])):
    raise SystemExit("ERROR: redaction did not record TEST_ONLY_SECRET")

if embedding.get("embedding_mode") != "stub":
    raise SystemExit("ERROR: embedding_mode is not stub")

if qdrant.get("mode") != "dry-run":
    raise SystemExit("ERROR: qdrant mode is not dry-run")
PY

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$(${commit_hash_script})"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker_part2}" <<EOF_MARKER
# Phase 16 Part 2 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make ai.index.doctor
- make ai.index.offline TENANT=platform SOURCE=docs
- make phase16.part2.entry.check

Result: PASS

Evidence:
- ${evidence_dir}

Statement:
Phase 16 Part 2 adds Qdrant ingestion/indexing for analysis only; no remediation or infra changes.
EOF_MARKER

self_hash_part2="$(sha256sum "${marker_part2}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_part2}"
} >>"${marker_part2}"
sha256sum "${marker_part2}" | awk '{print $1}' >"${marker_part2}.sha256"
