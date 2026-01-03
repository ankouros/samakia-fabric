#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker_part1="${acceptance_dir}/PHASE14_PART1_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase14.part1] ${label}"
  "$@"
}

extract_evidence_path() {
  awk '/runtime evaluation written to/ {print $NF}' | tail -n 1
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Operator docs anti-drift" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "Phase 14 Part 1 entry check" make -C "${FABRIC_REPO_ROOT}" phase14.part1.entry.check

real_output=$(TENANT=all make -C "${FABRIC_REPO_ROOT}" runtime.evaluate)
real_evidence_dir=$(printf '%s\n' "${real_output}" | extract_evidence_path)
if [[ -z "${real_evidence_dir}" ]]; then
  echo "ERROR: failed to capture runtime evaluation evidence path" >&2
  exit 1
fi

run_step "Runtime status" make -C "${FABRIC_REPO_ROOT}" runtime.status TENANT=all

synthetic_root="$(mktemp -d)"
trap 'rm -rf "${synthetic_root}" 2>/dev/null || true' EXIT

synthetic_stamp="20260103T000000Z"
mkdir -p "${synthetic_root}/evidence/drift/canary/${synthetic_stamp}"
cat >"${synthetic_root}/evidence/drift/canary/${synthetic_stamp}/classification.json" <<'JSON'
{
  "overall": {"class": "none", "severity": "info", "status": "PASS"},
  "signals": [],
  "sources": {"availability": "PASS", "capacity": "PASS", "configuration": "PASS", "security": "PASS"},
  "tenant": "canary",
  "timestamp": "2026-01-03T00:00:00Z"
}
JSON

mkdir -p "${synthetic_root}/evidence/bindings-verify/canary/${synthetic_stamp}"
cat >"${synthetic_root}/evidence/bindings-verify/canary/${synthetic_stamp}/results.json" <<'JSON'
[
  {
    "env": "dev",
    "results": [
      {
        "checks": {
          "provider": {"check": "postgres", "message": "offline", "mode": "offline", "status": "PASS"},
          "tcp_tls": {"check": "tcp_tls", "message": "offline", "mode": "offline", "status": "PASS"}
        },
        "consumer": {"provider": "postgres", "type": "database", "variant": "single"},
        "endpoint": {"host": "db.canary.internal", "port": 5432, "protocol": "tcp", "tls_required": true},
        "env": "dev",
        "mode": "offline",
        "status": "PASS",
        "tenant": "canary",
        "workload_id": "sample"
      }
    ],
    "status": "PASS",
    "tenant": "canary",
    "workload_id": "sample",
    "workload_type": "k8s"
  }
]
JSON

mkdir -p "${synthetic_root}/evidence/tenants/canary/${synthetic_stamp}/substrate-capacity"
cat >"${synthetic_root}/evidence/tenants/canary/${synthetic_stamp}/substrate-capacity/decision.json" <<'JSON'
{"overrides": [], "status": "PASS", "violations": []}
JSON

mkdir -p "${synthetic_root}/metrics/canary"
cat >"${synthetic_root}/metrics/canary/sample.json" <<'JSON'
{
  "timestamp_utc": "2026-01-03T00:00:00Z",
  "values": {
    "availability_percent": 95.0,
    "latency_p95_ms": 500,
    "latency_p99_ms": 800,
    "error_rate_percent": 2.0
  }
}
JSON

synthetic_output=$(TENANT=canary WORKLOAD=sample \
  DRIFT_EVIDENCE_ROOT="${synthetic_root}/evidence/drift" \
  VERIFY_EVIDENCE_ROOT="${synthetic_root}/evidence/bindings-verify" \
  TENANT_EVIDENCE_ROOT="${synthetic_root}/evidence/tenants" \
  RUNTIME_EVIDENCE_ROOT="${FABRIC_REPO_ROOT}/evidence/runtime-eval" \
  RUNTIME_STATUS_ROOT="${synthetic_root}/artifacts/runtime-status" \
  RUNTIME_EVAL_STAMP="${synthetic_stamp}" \
  METRICS_SOURCE_DIR="${synthetic_root}/metrics" \
  make -C "${FABRIC_REPO_ROOT}" runtime.evaluate)

synthetic_evidence_dir=$(printf '%s\n' "${synthetic_output}" | extract_evidence_path)
if [[ -z "${synthetic_evidence_dir}" ]]; then
  echo "ERROR: failed to capture synthetic runtime evaluation evidence path" >&2
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
# Phase 14 Part 1 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- make phase14.part1.entry.check
- make runtime.evaluate TENANT=all
- make runtime.status TENANT=all
- make runtime.evaluate TENANT=canary WORKLOAD=sample (synthetic fixtures)

Result: PASS

Evidence:
- ${real_evidence_dir}
- ${synthetic_evidence_dir}

Statement:
Runtime evaluation only; no remediation or automation performed.
EOF_MARKER

self_hash_part1="$(sha256sum "${marker_part1}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_part1}"
} >> "${marker_part1}"
sha256sum "${marker_part1}" | awk '{print $1}' > "${marker_part1}.sha256"
