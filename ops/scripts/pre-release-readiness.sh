#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage:
  pre-release-readiness.sh <release-id> <env>

Creates a local, derived readiness packet (ignored by Git):
  release-readiness/<release-id>/
    metadata.json
    checklist.md
    evidence-refs.txt
    manifest.sha256

Hard rules:
  - No infrastructure mutation, no signing, no network calls.
  - References evidence by path/hash; does not copy evidence packs.
  - Refuses dirty Git tree unless ALLOW_DIRTY_GIT=1.
EOF
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

release_id="${1:-}"
env_name="${2:-}"
if [[ -z "${release_id}" || -z "${env_name}" ]]; then
  usage
  exit 2
fi

require_cmd git
require_cmd date
require_cmd python3
require_cmd sha256sum
require_cmd find
require_cmd sort
require_cmd xargs

if [[ -z "${ALLOW_DIRTY_GIT:-}" ]]; then
  if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain=v1 2>/dev/null || true)" ]]; then
    echo "ERROR: working tree is dirty; readiness packets should map to a specific commit." >&2
    echo "Commit/stash changes or set ALLOW_DIRTY_GIT=1 (not recommended)." >&2
    exit 1
  fi
fi

ts_utc="$(date -u +%Y%m%dT%H%M%SZ)"
commit_full="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
commit_short="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

out_dir="${REPO_ROOT}/release-readiness/${release_id}"
mkdir -p "${out_dir}"

metadata_json="${out_dir}/metadata.json"
checklist_md="${out_dir}/checklist.md"
evidence_refs="${out_dir}/evidence-refs.txt"

latest_snapshot_dir=""
snap_root="${REPO_ROOT}/compliance/${env_name}"
if [[ -d "${snap_root}" ]]; then
  latest_snapshot_dir="$(
    find "${snap_root}" -maxdepth 1 -type d -name 'snapshot-*' -print \
      | LC_ALL=C sort \
      | tail -n 1
  )"
fi

latest_audit_dir=""
aud_root="${REPO_ROOT}/audit/${env_name}"
if [[ -d "${aud_root}" ]]; then
  latest_audit_dir="$(
    find "${aud_root}" -maxdepth 1 -type d -print \
      | rg -v "/${env_name}$" \
      | LC_ALL=C sort \
      | tail -n 1
  )"
fi

snapshot_manifest_ref="none"
if [[ -n "${latest_snapshot_dir}" && -f "${latest_snapshot_dir}/manifest.sha256" ]]; then
  sha="$(sha256sum "${latest_snapshot_dir}/manifest.sha256" | awk '{print $1}')"
  rel="${latest_snapshot_dir#"${REPO_ROOT}/"}"
  snapshot_manifest_ref="${rel}/manifest.sha256:sha256=${sha}"
fi

audit_report_ref="none"
if [[ -n "${latest_audit_dir}" && -f "${latest_audit_dir}/report.md" ]]; then
  sha="$(sha256sum "${latest_audit_dir}/report.md" | awk '{print $1}')"
  rel="${latest_audit_dir#"${REPO_ROOT}/"}"
  audit_report_ref="${rel}/report.md:sha256=${sha}"
fi

python3 - "${metadata_json}" "${release_id}" "${env_name}" "${ts_utc}" "${commit_full}" "${commit_short}" "${snapshot_manifest_ref}" "${audit_report_ref}" <<'PY'
import json
import sys

out, release_id, env_name, ts, commit_full, commit_short, snap_ref, audit_ref = sys.argv[1:9]

doc = {
  "release_id": release_id,
  "environment": env_name,
  "timestamp_utc": ts,
  "git_commit": commit_full,
  "git_commit_short": commit_short,
  "auto_discovered": {
    "latest_compliance_snapshot_manifest_ref": None if snap_ref == "none" else snap_ref,
    "latest_drift_audit_report_ref": None if audit_ref == "none" else audit_ref,
  },
  "notes": [
    "This packet is derived analysis output. It references evidence packs; it is not evidence itself.",
    "Signatures (if applied) prove integrity of this packet, not correctness of conclusions.",
  ],
}

with open(out, "w", encoding="utf-8") as f:
  json.dump(doc, f, indent=2, sort_keys=True)
  f.write("\n")
PY

{
  echo "# Evidence references (read-only)"
  echo
  echo "release_id=${release_id}"
  echo "env=${env_name}"
  echo "timestamp_utc=${ts_utc}"
  echo "git_commit=${commit_full}"
  echo
  echo "latest_compliance_snapshot_manifest_ref=${snapshot_manifest_ref}"
  echo "latest_drift_audit_report_ref=${audit_report_ref}"
  echo
  echo "# Add additional references in the form:"
  echo "# <path>:sha256=<sha256>"
  echo "# Do not paste large evidence content here."
} >"${evidence_refs}"

{
  echo "# Pre-Release Readiness Checklist — ${release_id} (${env_name})"
  echo
  echo "- Timestamp (UTC): \`${ts_utc}\`"
  echo "- Git commit: \`${commit_full}\`"
  echo
  echo "Evidence pointers (auto-discovered if present):"
  echo "- Latest compliance snapshot: \`${snapshot_manifest_ref}\`"
  echo "- Latest drift audit report: \`${audit_report_ref}\`"
  echo
  echo "Mark each item: **PASS / FAIL / ACCEPTED RISK / N/A**"
  echo
  echo "## Platform health"
  echo "- [ ] Quorum healthy (evidence: )"
  echo "- [ ] HA manager healthy (evidence: )"
  echo "- [ ] No unresolved HA alerts/flapping (evidence: )"
  echo "- [ ] Recent HA GameDay exists or exception approved (evidence: )"
  echo
  echo "## Configuration integrity"
  echo "- [ ] Terraform plan clean or understood (evidence: )"
  echo "- [ ] Drift audit reviewed (evidence: ${audit_report_ref})"
  echo "- [ ] No unmanaged critical resources (evidence: )"
  echo
  echo "## Compliance & evidence"
  echo "- [ ] Compliance snapshot exists (evidence: ${snapshot_manifest_ref})"
  echo "- [ ] Snapshot verified (signature/TSA per policy) (evidence: )"
  echo "- [ ] No open legal holds blocking release (evidence: )"
  echo
  echo "## Application readiness"
  echo "- [ ] App evidence collected (evidence: )"
  echo "- [ ] Known vulns assessed/documented (evidence: )"
  echo "- [ ] Backup/restore evidence exists (evidence: )"
  echo
  echo "## Incident posture"
  echo "- [ ] No unresolved S3/S4 incidents (evidence: )"
  echo "- [ ] Correlation reviewed if applicable (evidence: )"
  echo "- [ ] Forensics packets closed or accepted (evidence: )"
  echo
  echo "## Threat & risk review"
  echo "- [ ] Threat model reviewed for scope (evidence: SECURITY_THREAT_MODELING.md)"
  echo "- [ ] No unaccepted high-risk residuals (evidence: )"
  echo "- [ ] New risks acknowledged (evidence: )"
  echo
  echo "## Go / No-Go"
  echo "- Decision: **GO / NO-GO**"
  echo "- Approvers:"
  echo "  - Platform/SRE:"
  echo "  - Security:"
  echo "  - Service owner(s):"
  echo "  - Legal (if applicable):"
  echo "- Risk acceptance record (if any): risk-acceptance.md"
} >"${checklist_md}"

# Derived manifest for the readiness packet (exclude legal-hold labels if present)
(
  cd "${out_dir}"
  find . \
    -path './legal-hold' -prune -o \
    -type f \
    ! -name 'manifest.sha256' \
    ! -name 'manifest.sha256.asc' \
    ! -name 'manifest.sha256.asc.a' \
    ! -name 'manifest.sha256.asc.b' \
    ! -name 'manifest.sha256.tsr' \
    ! -name 'tsa-metadata.json' \
    -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >manifest.sha256
)

echo "OK: wrote readiness packet: ${out_dir}"
echo "Next (optional): sign/notarize it via:"
echo "  COMPLIANCE_SNAPSHOT_DIR=\"${out_dir}\" bash ops/scripts/compliance-snapshot.sh ${env_name}"
