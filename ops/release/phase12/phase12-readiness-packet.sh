#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  phase12-readiness-packet.sh TENANT=<id|all>

Environment:
  TENANT=all|<id> (default: all)
  ENV=<env name> (optional; used for signing rules)
  READINESS_STAMP=<UTC timestamp> (optional; overrides timestamp)
  READINESS_SIGN=1 (optional; force signature)
  CI=1 (optional; skip signing unless READINESS_SIGN=1)
  PHASE12_PACKET_ROOT=<path> (optional; default: evidence/release-readiness/phase12)
EOT
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_cmd date
require_cmd find
require_cmd python3
require_cmd sha256sum
require_cmd sort

TENANT="${TENANT:-all}"
ENV_NAME="${ENV:-}"
stamp="${READINESS_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
packet_root="${PHASE12_PACKET_ROOT:-${FABRIC_REPO_ROOT}/evidence/release-readiness/phase12}"
packet_dir="${packet_root}/${stamp}"
parts_dir="${packet_dir}/parts"
docs_dir="${packet_dir}/docs"
samples_dir="${packet_dir}/samples"

mkdir -p "${parts_dir}" "${docs_dir}" "${samples_dir}"

commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$(${commit_hash_script} 2>/dev/null || true)"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD 2>/dev/null || true)"
fi
commit_hash="${commit_hash:-unknown}"

sign_manifest=0
if [[ "${READINESS_SIGN:-0}" == "1" ]]; then
  sign_manifest=1
fi
if [[ "${ENV_NAME}" == "samakia-prod" || "${ENV_NAME}" == "prod" ]]; then
  sign_manifest=1
fi
if [[ "${CI:-0}" == "1" && "${READINESS_SIGN:-0}" != "1" ]]; then
  sign_manifest=0
fi

run_cmd() {
  local label="$1"
  local cmd="$2"
  echo "[phase12.readiness] ${label}"
  set +e
  CI=1 bash -c "${cmd}"
  local rc=$?
  set -e
  if [[ ${rc} -ne 0 ]]; then
    echo "[phase12.readiness] FAIL: ${label}" >&2
  fi
  return ${rc}
}

overall_status="PASS"

gate_policy_status="PASS"
policy_cmd="make -C \"${FABRIC_REPO_ROOT}\" policy.check"
if ! run_cmd "Policy gate" "${policy_cmd}"; then
  gate_policy_status="FAIL"
  overall_status="FAIL"
fi

gate_docs_status="PASS"
docs_cmd="make -C \"${FABRIC_REPO_ROOT}\" docs.operator.check"
if ! run_cmd "Operator docs anti-drift" "${docs_cmd}"; then
  gate_docs_status="FAIL"
  overall_status="FAIL"
fi

part1_status="PASS"
part1_cmds=(
  "TENANT=\"${TENANT}\" make -C \"${FABRIC_REPO_ROOT}\" bindings.validate"
  "TENANT=\"${TENANT}\" make -C \"${FABRIC_REPO_ROOT}\" bindings.render"
)
for cmd in "${part1_cmds[@]}"; do
  if ! run_cmd "Part 1" "${cmd}"; then
    part1_status="FAIL"
    overall_status="FAIL"
  fi
 done

part2_status="PASS"
part2_cmds=(
  "TENANT=\"${TENANT}\" make -C \"${FABRIC_REPO_ROOT}\" bindings.secrets.inspect"
)
for cmd in "${part2_cmds[@]}"; do
  if ! run_cmd "Part 2" "${cmd}"; then
    part2_status="FAIL"
    overall_status="FAIL"
  fi
 done

part3_status="PASS"
part3_cmds=(
  "TENANT=\"${TENANT}\" make -C \"${FABRIC_REPO_ROOT}\" bindings.verify.offline"
)
for cmd in "${part3_cmds[@]}"; do
  if ! run_cmd "Part 3" "${cmd}"; then
    part3_status="FAIL"
    overall_status="FAIL"
  fi
 done

part4_status="PASS"
part4_cmds=(
  "make -C \"${FABRIC_REPO_ROOT}\" proposals.validate PROPOSAL_ID=example"
  "make -C \"${FABRIC_REPO_ROOT}\" proposals.review PROPOSAL_ID=add-postgres-binding"
  "make -C \"${FABRIC_REPO_ROOT}\" proposals.review PROPOSAL_ID=increase-cache-capacity"
)
for cmd in "${part4_cmds[@]}"; do
  if ! run_cmd "Part 4" "${cmd}"; then
    part4_status="FAIL"
    overall_status="FAIL"
  fi
 done

part5_status="PASS"
part5_cmds=(
  "TENANT=\"${TENANT}\" DRIFT_OFFLINE=1 DRIFT_NON_BLOCKING=1 DRIFT_FAIL_ON=none DRIFT_REQUIRE_SIGN=0 make -C \"${FABRIC_REPO_ROOT}\" drift.detect"
  "TENANT=\"${TENANT}\" make -C \"${FABRIC_REPO_ROOT}\" drift.summary"
)
for cmd in "${part5_cmds[@]}"; do
  if ! run_cmd "Part 5" "${cmd}"; then
    part5_status="FAIL"
    overall_status="FAIL"
  fi
 done

part1_out="${parts_dir}/part1-bindings.json"
PART_STATUS="${part1_status}" PART_COMMANDS="$(printf '%s\n' "${part1_cmds[@]}")" \
TENANT="${TENANT}" OUT_FILE="${part1_out}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])
tenant = os.environ.get("TENANT", "all")
status = os.environ.get("PART_STATUS", "UNKNOWN")
commands = [line for line in os.environ.get("PART_COMMANDS", "").splitlines() if line]

bindings = []
renders = []
if tenant == "all":
    bindings_root = root / "contracts" / "bindings" / "tenants"
    if bindings_root.exists():
        for path in sorted(bindings_root.rglob("*.binding.yml")):
            bindings.append(str(path.relative_to(root)))
    renders_root = root / "artifacts" / "bindings"
    if renders_root.exists():
        for path in sorted(renders_root.rglob("connection.json")):
            renders.append(str(path.relative_to(root)))
else:
    bindings_root = root / "contracts" / "bindings" / "tenants" / tenant
    if bindings_root.exists():
        for path in sorted(bindings_root.glob("*.binding.yml")):
            bindings.append(str(path.relative_to(root)))
    renders_root = root / "artifacts" / "bindings" / tenant
    if renders_root.exists():
        for path in sorted(renders_root.rglob("connection.json")):
            renders.append(str(path.relative_to(root)))

payload = {
    "part": "part1",
    "title": "Tenant bindings (contract-only)",
    "status": status,
    "tenant": tenant,
    "bindings_count": len(bindings),
    "render_count": len(renders),
    "bindings": bindings,
    "renders": renders,
    "contracts": [
        "contracts/bindings/binding.schema.json",
        "contracts/bindings/tenants/",
    ],
    "commands": commands,
    "notes": [
        "Render output is redacted connection manifests only.",
        "No secrets are present in bindings or renders.",
    ],
}

Path(os.environ["OUT_FILE"]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

part2_raw="${parts_dir}/part2-secrets.raw.json"
PART_STATUS="${part2_status}" PART_COMMANDS="$(printf '%s\n' "${part2_cmds[@]}")" \
TENANT="${TENANT}" OUT_FILE="${part2_raw}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - <<'PY'
import json
import os
from pathlib import Path
import yaml

root = Path(os.environ["FABRIC_REPO_ROOT"])
tenant_filter = os.environ.get("TENANT", "all")
status = os.environ.get("PART_STATUS", "UNKNOWN")
commands = [line for line in os.environ.get("PART_COMMANDS", "").splitlines() if line]

bindings_root = root / "contracts" / "bindings" / "tenants"
bindings = []
if bindings_root.exists():
    bindings = sorted(bindings_root.rglob("*.binding.yml"))

entries = []
for binding in bindings:
    data = yaml.safe_load(binding.read_text())
    meta = data.get("metadata", {})
    tenant = meta.get("tenant", "")
    env = meta.get("env", "")
    if tenant_filter != "all" and tenant != tenant_filter:
        continue
    for consumer in data.get("spec", {}).get("consumers", []) or []:
        entries.append({
            "tenant": tenant,
            "env": env,
            "secret_ref": consumer.get("secret_ref"),
            "secret_shape": consumer.get("secret_shape"),
            "credential_source": consumer.get("credential_source"),
            "provider": consumer.get("provider"),
        })

payload = {
    "part": "part2",
    "title": "Binding secrets (inspect-only)",
    "status": status,
    "tenant": tenant_filter,
    "secret_entries": entries,
    "secret_entries_count": len(entries),
    "contracts": [
        "contracts/secrets/shapes/",
        "docs/bindings/secrets.md",
    ],
    "commands": commands,
    "notes": [
        "secret_ref values are redacted in the readiness packet.",
        "Execute materialization/rotation is guarded and never allowed in CI.",
    ],
}

Path(os.environ["OUT_FILE"]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

"${FABRIC_REPO_ROOT}/ops/release/phase12/phase12-readiness-redact.sh" "${part2_raw}" "${parts_dir}/part2-secrets.json"
rm -f "${part2_raw}"

part3_out="${parts_dir}/part3-verify.json"
PART_STATUS="${part3_status}" PART_COMMANDS="$(printf '%s\n' "${part3_cmds[@]}")" \
TENANT="${TENANT}" OUT_FILE="${part3_out}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])
tenant_filter = os.environ.get("TENANT", "all")
status = os.environ.get("PART_STATUS", "UNKNOWN")
commands = [line for line in os.environ.get("PART_COMMANDS", "").splitlines() if line]

verify_root = root / "evidence" / "bindings-verify"

entries = []

def latest_run(path: Path):
    if not path.exists():
        return None
    runs = sorted([p for p in path.iterdir() if p.is_dir()])
    return runs[-1] if runs else None

if tenant_filter == "all":
    tenants = sorted([p.name for p in verify_root.iterdir() if p.is_dir()]) if verify_root.exists() else []
else:
    tenants = [tenant_filter]

for tenant in tenants:
    tenant_dir = verify_root / tenant
    latest = latest_run(tenant_dir)
    if not latest:
        entries.append({"tenant": tenant, "status": "MISSING", "latest_run": None})
        continue
    results_path = latest / "results.json"
    summary = {"tenant": tenant, "latest_run": latest.name, "status": "UNKNOWN"}
    if results_path.exists():
        data = json.loads(results_path.read_text())
        counts = {"PASS": 0, "WARN": 0, "FAIL": 0}
        for item in data:
            result = item.get("status")
            if result in counts:
                counts[result] += 1
        summary.update({"status": "PASS" if counts.get("FAIL", 0) == 0 else "FAIL", "counts": counts})
    entries.append(summary)

payload = {
    "part": "part3",
    "title": "Bindings verification (offline)",
    "status": status,
    "tenant": tenant_filter,
    "runs": entries,
    "evidence_root": "evidence/bindings-verify",
    "commands": commands,
    "notes": [
        "Live verification is guarded and forbidden in CI.",
        "Offline verification uses rendered manifests only.",
    ],
}

Path(os.environ["OUT_FILE"]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

part4_out="${parts_dir}/part4-proposals.json"
PART_STATUS="${part4_status}" PART_COMMANDS="$(printf '%s\n' "${part4_cmds[@]}")" \
OUT_FILE="${part4_out}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])
status = os.environ.get("PART_STATUS", "UNKNOWN")
commands = [line for line in os.environ.get("PART_COMMANDS", "").splitlines() if line]

examples_dir = root / "examples" / "proposals"
examples = sorted([str(p.relative_to(root)) for p in examples_dir.glob("*.yml")]) if examples_dir.exists() else []

payload = {
    "part": "part4",
    "title": "Proposal workflow (optional)",
    "status": status,
    "examples": examples,
    "contracts": [
        "contracts/proposals/proposal.schema.json",
        "examples/proposals/",
    ],
    "commands": commands,
    "notes": [
        "Approvals and apply are operator-controlled and forbidden in CI.",
        "Use proposals.approve/proposals.apply only with explicit guards.",
    ],
}

Path(os.environ["OUT_FILE"]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

part5_out="${parts_dir}/part5-drift.json"
PART_STATUS="${part5_status}" PART_COMMANDS="$(printf '%s\n' "${part5_cmds[@]}")" \
TENANT="${TENANT}" OUT_FILE="${part5_out}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])
tenant_filter = os.environ.get("TENANT", "all")
status = os.environ.get("PART_STATUS", "UNKNOWN")
commands = [line for line in os.environ.get("PART_COMMANDS", "").splitlines() if line]

summaries = []
summary_root = root / "artifacts" / "tenant-status"

if tenant_filter == "all":
    tenants = sorted([p.name for p in summary_root.iterdir() if p.is_dir()]) if summary_root.exists() else []
else:
    tenants = [tenant_filter]

for tenant in tenants:
    summary_path = summary_root / tenant / "drift-summary.json"
    if summary_path.exists():
        payload = json.loads(summary_path.read_text())
        summaries.append({
            "tenant": tenant,
            "overall": payload.get("overall"),
            "status": payload.get("overall", {}).get("status"),
            "severity": payload.get("overall", {}).get("severity"),
            "summary_path": str(summary_path.relative_to(root)),
        })
    else:
        summaries.append({"tenant": tenant, "status": "MISSING", "summary_path": None})

payload = {
    "part": "part5",
    "title": "Drift awareness (read-only)",
    "status": status,
    "tenant": tenant_filter,
    "summaries": summaries,
    "contracts": [
        "docs/drift/taxonomy.md",
        "ops/drift/",
    ],
    "commands": commands,
    "notes": [
        "Drift signals are read-only; no remediation is executed.",
        "Alert routing defaults are evidence-only.",
    ],
}

Path(os.environ["OUT_FILE"]).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
PY

cat >"${docs_dir}/proposal-flow.md" <<'EOF_DOC'
# Phase 12 Proposal Flow (Optional)

This is a read-only summary for the optional proposal workflow.

Canonical commands live in:
- docs/operator/cookbook.md

Contract references:
- contracts/proposals/proposal.schema.json
- examples/proposals/

Read-only flow:
- make proposals.submit FILE=examples/proposals/add-postgres-binding.yml
- make proposals.validate PROPOSAL_ID=example
- make proposals.review PROPOSAL_ID=add-postgres-binding

Guarded flow (never in CI):
- OPERATOR_APPROVE=1 APPROVER_ID="ops-01" make proposals.approve PROPOSAL_ID=add-postgres-binding
- APPLY_DRYRUN=1 make proposals.apply PROPOSAL_ID=add-postgres-binding
- PROPOSAL_APPLY=1 BIND_EXECUTE=1 make proposals.apply PROPOSAL_ID=add-postgres-binding
EOF_DOC

cp "${FABRIC_REPO_ROOT}/docs/operator/cookbook.md" "${docs_dir}/operator-cookbook.md"
cp "${FABRIC_REPO_ROOT}/docs/bindings/README.md" "${docs_dir}/binding-contract.md"
cp "${FABRIC_REPO_ROOT}/docs/drift/taxonomy.md" "${docs_dir}/drift-taxonomy.md"

cat >"${samples_dir}/sample-tenant-status.md" <<'EOF_SAMPLE'
# Sample Tenant Drift Summary

Tenant: project-sample
Timestamp (UTC): 2026-01-01T00:00:00Z
Run: 2026-01-01T00:00:00Z

Overall: warn (WARN)

Tenant-visible signals:
- warn capacity: Example signal summary
- info bindings: Example signal summary

Operator-only signals are present. Contact the operator team for details.
EOF_SAMPLE

summary_file="${packet_dir}/summary.md"
{
  echo "# Phase 12 Release Readiness Summary"
  echo
  echo "Timestamp (UTC): ${stamp}"
  echo "Commit: ${commit_hash}"
  if [[ -n "${ENV_NAME}" ]]; then
    echo "Environment: ${ENV_NAME}"
  fi
  echo "Tenant scope: ${TENANT}"
  echo "Overall status: ${overall_status}"
  echo
  echo "## Global gates"
  echo "- policy.check: ${gate_policy_status}"
  echo "- docs.operator.check: ${gate_docs_status}"
  echo
  echo "## Part status"
  echo "- Part 1 (bindings): ${part1_status}"
  echo "- Part 2 (secrets inspect): ${part2_status}"
  echo "- Part 3 (offline verify): ${part3_status}"
  echo "- Part 4 (proposals): ${part4_status}"
  echo "- Part 5 (drift): ${part5_status}"
  echo
  echo "## Reproduction commands"
  echo "- ${policy_cmd}"
  echo "- ${docs_cmd}"
  printf '%s\n' "${part1_cmds[@]}" | sed 's/^/- /'
  printf '%s\n' "${part2_cmds[@]}" | sed 's/^/- /'
  printf '%s\n' "${part3_cmds[@]}" | sed 's/^/- /'
  printf '%s\n' "${part4_cmds[@]}" | sed 's/^/- /'
  printf '%s\n' "${part5_cmds[@]}" | sed 's/^/- /'
  echo
  echo "## Contract references"
  echo "- contracts/bindings/binding.schema.json"
  echo "- contracts/secrets/shapes/"
  echo "- contracts/proposals/proposal.schema.json"
  echo "- docs/drift/taxonomy.md"
  echo
  echo "## Exposure controls"
  echo "Allowed: read-only validation, render, offline verify, drift detect/summary, proposal review."
  echo "Forbidden: live verify in CI, secret materialization/rotation without guard, proposal approval/apply in CI."
} >"${summary_file}"

cat >"${packet_dir}/README.md" <<EOF_README
# Phase 12 Release Readiness Packet

This packet is a deterministic, redacted readiness bundle for Phase 12 workload exposure.

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}
Environment: ${ENV_NAME:-unspecified}
Tenant scope: ${TENANT}
Overall status: ${overall_status}

Contents:
- summary.md: PASS/FAIL summary and reproduction commands
- parts/: machine-readable per-part summaries
- docs/: operator and contract references
- samples/: sample tenant status output
- manifest.json + manifest.sha256: integrity metadata

Integrity verification:
- sha256sum -c manifest.sha256

No secrets are included in this packet.
EOF_README

MANIFEST_STAMP="${stamp}" \
MANIFEST_COMMIT="${commit_hash}" \
MANIFEST_ENV="${ENV_NAME:-unspecified}" \
MANIFEST_TENANT="${TENANT}" \
MANIFEST_STATUS="${overall_status}" \
  bash "${FABRIC_REPO_ROOT}/ops/release/phase12/phase12-readiness-manifest.sh" "${packet_dir}"

if [[ "${sign_manifest}" -eq 1 ]]; then
  if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg not found; required for readiness signing" >&2
    exit 1
  fi
  gpg --batch --yes --detach-sign --armor --output "${packet_dir}/manifest.sha256.asc" "${packet_dir}/manifest.sha256"
fi

echo "OK: wrote Phase 12 readiness packet to ${packet_dir}"
