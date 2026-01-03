#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker_part4="${acceptance_dir}/PHASE16_PART4_ACCEPTED.md"

run_step() {
  local label="$1"
  shift
  echo "[phase16.part4] ${label}"
  "$@"
}

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_step "Pre-commit" pre-commit run --all-files
run_step "Lint" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/lint.sh"
run_step "Validate" bash "${FABRIC_REPO_ROOT}/fabric-ci/scripts/validate.sh"
run_step "Policy gates" make -C "${FABRIC_REPO_ROOT}" policy.check
run_step "Operator docs check" make -C "${FABRIC_REPO_ROOT}" docs.operator.check
run_step "Phase 16 Part 4 entry check" make -C "${FABRIC_REPO_ROOT}" phase16.part4.entry.check

fixtures_root="${FABRIC_REPO_ROOT}/evidence/ai/analysis"
mkdir -p "${fixtures_root}/canary/fixtures" "${fixtures_root}/platform/fixtures"
mkdir -p "${FABRIC_REPO_ROOT}/tmp"

cat >"${fixtures_root}/canary/fixtures/drift-summary.md" <<'EOF_FIXTURE'
Tenant: canary
Drift summary:
- 2 resources differ
EOF_FIXTURE

cat >"${fixtures_root}/canary/fixtures/incident.md" <<'EOF_FIXTURE'
Tenant: canary
Incident summary:
- Signal: credentials removed
- Impact: reduced availability
EOF_FIXTURE

cat >"${fixtures_root}/platform/fixtures/plan.txt" <<'EOF_FIXTURE'
Plan: 1 to add, 0 to change, 0 to destroy
EOF_FIXTURE

evidence_port=8782
pids=()

start_server() {
  local name="$1"
  local port="$2"
  local script="$3"
  MCP_TEST_MODE=1 MCP_PORT="${port}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" \
    bash "${script}" >"${FABRIC_REPO_ROOT}/tmp/ai-analysis-${name}.log" 2>&1 &
  pids+=("$!")
  for _ in {1..30}; do
    if curl -sS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
      return
    fi
    sleep 0.2
  done
  echo "ERROR: ${name} MCP failed to start on port ${port}" >&2
  exit 1
}

cleanup() {
  for pid in "${pids[@]}"; do
    kill "${pid}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

start_server "evidence" "${evidence_port}" "${FABRIC_REPO_ROOT}/ops/ai/mcp/evidence/server.sh"

run_step "AI analysis plan (drift explain)" \
  env MCP_EVIDENCE_URL="http://127.0.0.1:${evidence_port}" \
  make -C "${FABRIC_REPO_ROOT}" ai.analyze.plan FILE=examples/analysis/drift_explain.yml

analysis_id_incident="$(ANALYSIS_PATH="${FABRIC_REPO_ROOT}/examples/analysis/incident_summary.yml" python3 - <<'PY'
import os
import yaml

payload = yaml.safe_load(open(os.environ["ANALYSIS_PATH"], "r", encoding="utf-8"))
print(payload.get("analysis_id"))
PY
)"

incident_out="${FABRIC_REPO_ROOT}/evidence/ai/analysis/${analysis_id_incident}/$(date -u +%Y%m%dT%H%M%SZ)"

run_step "AI analysis plan (incident summary)" \
  env MCP_EVIDENCE_URL="http://127.0.0.1:${evidence_port}" \
  bash "${FABRIC_REPO_ROOT}/ops/ai/analysis/analyze.sh" plan \
  --file "${FABRIC_REPO_ROOT}/examples/analysis/incident_summary.yml" \
  --out-dir "${incident_out}"

analysis_id_plan="$(ANALYSIS_PATH="${FABRIC_REPO_ROOT}/examples/analysis/plan_review.yml" python3 - <<'PY'
import os
import yaml

payload = yaml.safe_load(open(os.environ["ANALYSIS_PATH"], "r", encoding="utf-8"))
print(payload.get("analysis_id"))
PY
)"

plan_out="${FABRIC_REPO_ROOT}/evidence/ai/analysis/${analysis_id_plan}/$(date -u +%Y%m%dT%H%M%SZ)"

run_step "AI analysis plan (plan review)" \
  env MCP_EVIDENCE_URL="http://127.0.0.1:${evidence_port}" \
  bash "${FABRIC_REPO_ROOT}/ops/ai/analysis/analyze.sh" plan \
  --file "${FABRIC_REPO_ROOT}/examples/analysis/plan_review.yml" \
  --out-dir "${plan_out}"

latest_drift_dir="$(find "${FABRIC_REPO_ROOT}/evidence/ai/analysis/drift-explain-canary" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort | tail -n1)"
if [[ -z "${latest_drift_dir}" ]]; then
  echo "ERROR: drift explain output not found" >&2
  exit 1
fi

drift_out="${FABRIC_REPO_ROOT}/evidence/ai/analysis/drift-explain-canary/${latest_drift_dir}"

for dir in "${drift_out}" "${incident_out}" "${plan_out}"; do
  for file in analysis.yml.redacted inputs.json prompt.md model.json output.md manifest.sha256; do
    if [[ ! -f "${dir}/${file}" ]]; then
      echo "ERROR: missing evidence file ${dir}/${file}" >&2
      exit 1
    fi
  done
  if [[ ! -f "${dir}/context.md" ]]; then
    echo "ERROR: missing context file ${dir}/context.md" >&2
    exit 1
  fi
done

if ! rg -n "id: redacted" "${incident_out}/analysis.yml.redacted" >/dev/null 2>&1; then
  echo "ERROR: tenant id not redacted in incident analysis" >&2
  exit 1
fi

if rg -n "token" "${incident_out}/inputs.json" >/dev/null 2>&1; then
  echo "ERROR: token leaked in incident inputs" >&2
  exit 1
fi

if ! rg -n "REDACTED_TENANT" "${incident_out}/inputs.json" >/dev/null 2>&1; then
  echo "ERROR: tenant redaction missing in incident inputs" >&2
  exit 1
fi

mkdir -p "${acceptance_dir}"
commit_hash_script="${FABRIC_REPO_ROOT}/ops/scripts/git-commit-hash.sh"
if [[ -x "${commit_hash_script}" ]]; then
  commit_hash="$(${commit_hash_script})"
else
  commit_hash="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)"
fi

cat >"${marker_part4}" <<EOF_MARKER
# Phase 16 Part 4 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- pre-commit run --all-files
- bash fabric-ci/scripts/lint.sh
- bash fabric-ci/scripts/validate.sh
- make policy.check
- make docs.operator.check
- make phase16.part4.entry.check
- make ai.analyze.plan FILE=examples/analysis/drift_explain.yml
- ops/ai/analysis/analyze.sh plan --file examples/analysis/incident_summary.yml --out-dir ${incident_out}
- ops/ai/analysis/analyze.sh plan --file examples/analysis/plan_review.yml --out-dir ${plan_out}

Result: PASS

Evidence:
- ${drift_out}
- ${incident_out}
- ${plan_out}

Statement:
AI analysis is read-only and evidence-bound; no actions or remediation were introduced.
EOF_MARKER

self_hash_part4="$(sha256sum "${marker_part4}" | awk '{print $1}')"
{
  echo
  echo "Self-hash (sha256 of content above): ${self_hash_part4}"
} >>"${marker_part4}"
sha256sum "${marker_part4}" | awk '{print $1}' >"${marker_part4}.sha256"
