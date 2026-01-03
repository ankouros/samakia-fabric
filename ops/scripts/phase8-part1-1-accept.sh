#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE8_PART1_1_ACCEPTED.md"

run_cmd() {
  echo "[phase8.part1.1] $*"
  "$@"
}

run_cmd make -C "$FABRIC_REPO_ROOT" policy.check
run_cmd make -C "$FABRIC_REPO_ROOT" phase8.entry.check
run_cmd make -C "$FABRIC_REPO_ROOT" images.vm.validate.contracts
run_cmd make -C "$FABRIC_REPO_ROOT" image.tools.check

if [[ ! -x "$FABRIC_REPO_ROOT/ops/images/vm/local-run.sh" ]]; then
  echo "ERROR: local-run.sh missing or not executable" >&2
  exit 1
fi
if [[ ! -x "$FABRIC_REPO_ROOT/ops/images/vm/evidence/verify-evidence.sh" ]]; then
  echo "ERROR: verify-evidence.sh missing or not executable" >&2
  exit 1
fi

fixture_note="QCOW2_FIXTURE_PATH not set; local validation is operator-only"
if [[ -n "${QCOW2_FIXTURE_PATH:-}" ]]; then
  fixture_note="QCOW2_FIXTURE_PATH provided; offline validation executed"
  image="${IMAGE:-ubuntu-24.04}"
  version="${VERSION:-v1}"
  run_cmd "$FABRIC_REPO_ROOT/ops/images/vm/local-run.sh" validate --image "$image" --version "$version" --qcow2 "$QCOW2_FIXTURE_PATH"
  run_cmd "$FABRIC_REPO_ROOT/ops/images/vm/local-run.sh" evidence --image "$image" --version "$version" --qcow2 "$QCOW2_FIXTURE_PATH"
fi

mkdir -p "$acceptance_dir"
commit_hash="$("${FABRIC_REPO_ROOT}"/ops/scripts/git-commit-hash.sh 2>/dev/null || git -C "$FABRIC_REPO_ROOT" rev-parse HEAD)"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"$marker" <<EOF_MARKER
# Phase 8 Part 1.1 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- make policy.check
- make phase8.entry.check
- make images.vm.validate.contracts
- make image.tools.check
- local-run validate/evidence (only if QCOW2_FIXTURE_PATH set)

Result: PASS
Notes: ${fixture_note}

Statement:
Local operator runbook and safe wrapper implemented; no Proxmox and no VM provisioning.
EOF_MARKER

( cd "$acceptance_dir" && sha256sum "$(basename "$marker")" >"$(basename "$marker").sha256" )
