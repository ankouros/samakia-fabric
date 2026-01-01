#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE11_PART5_ROUTING_ACCEPTED.md"
config_path="${FABRIC_REPO_ROOT}/contracts/alerting/routing.yml"

run_step() {
  local label="$1"
  shift
  echo "[phase11.part5] ${label}"
  "$@"
}

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Routing validation" make -C "${FABRIC_REPO_ROOT}" substrate.alert.validate
run_step "Phase 11 Part 5 entry check" make -C "${FABRIC_REPO_ROOT}" phase11.part5.entry.check

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "${config_path}" "${FABRIC_REPO_ROOT}" "${stamp}" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
stamp = sys.argv[3]

routing = json.loads(config_path.read_text())

for env in ("samakia-dev", "samakia-shared", "samakia-prod"):
    env_cfg = routing["envs"][env]
    out_dir = repo_root / "evidence" / "alerts" / env / stamp
    out_dir.mkdir(parents=True, exist_ok=True)
    report = out_dir / "report.md"
    warn_map = env_cfg["severity_mapping"]["WARN"]
    fail_map = env_cfg["severity_mapping"]["FAIL"]
    delivery_enabled = env_cfg["delivery"]["enabled"]
    report.write_text(
        "# Drift Alert Simulation\n\n"
        f"Environment: {env}\n"
        f"Timestamp (UTC): {stamp}\n\n"
        "Simulated events:\n"
        f"- WARN mapped to {warn_map}\n"
        f"- FAIL mapped to {fail_map}\n\n"
        f"Delivery enabled: {delivery_enabled}\n\n"
        "Result: Evidence written only; no external delivery.\n"
    )
    manifest = out_dir / "manifest.sha256"
    sha = report.read_bytes()
    import hashlib
    digest = hashlib.sha256(sha).hexdigest()
    manifest.write_text(f"{digest}  report.md\n")
PY

mkdir -p "${acceptance_dir}"
commit_hash="$("${FABRIC_REPO_ROOT}"/ops/scripts/git-commit-hash.sh 2>/dev/null || git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"

cat >"${marker}" <<EOF_MARKER
# Phase 11 Part 5 Routing Defaults Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make substrate.alert.validate
- make phase11.part5.entry.check

Result: PASS

Statement:
Routing defaults emit drift alerts as evidence only. No remediation or external delivery is enabled by default.
EOF_MARKER

self_hash="$(sha256sum "${marker}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash}"
} >> "${marker}"
sha256sum "${marker}" | awk '{print $1}' > "${marker}.sha256"
