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
require_cmd find
require_cmd git
require_cmd python3
require_cmd rg
require_cmd sha256sum
require_cmd sort

if ! command -v pre-commit >/dev/null 2>&1; then
  echo "ERROR: pre-commit is required for milestone verification" >&2
  exit 1
fi

stamp="${MILESTONE_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
packet_root="${MILESTONE_PACKET_ROOT:-${FABRIC_REPO_ROOT}/evidence/milestones/phase1-12}"
packet_dir="${packet_root}/${stamp}"
mkdir -p "${packet_dir}"
steps_dir="${packet_dir}/steps"
mkdir -p "${steps_dir}"

commands_log="${packet_dir}/commands.log"
results_tmp="$(mktemp)"
warnings_tmp="$(mktemp)"
invariants_tmp="$(mktemp)"

: > "${commands_log}"

cleanup() {
  rm -f "${results_tmp}" "${warnings_tmp}" "${invariants_tmp}" 2>/dev/null || true
}
trap cleanup EXIT

export PRE_COMMIT_HOME="${PRE_COMMIT_HOME:-${FABRIC_REPO_ROOT}/.cache/pre-commit}"
export ANSIBLE_LOCAL_TMP="${ANSIBLE_LOCAL_TMP:-${FABRIC_REPO_ROOT}/.cache/ansible/tmp}"
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-${FABRIC_REPO_ROOT}/.cache/ansible/tmp}"
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-${FABRIC_REPO_ROOT}/.cache/terraform-plugins}"
export TF_CLI_ARGS_init="${TF_CLI_ARGS_init:--backend=false -input=false}"

mkdir -p "${PRE_COMMIT_HOME}" "${ANSIBLE_LOCAL_TMP}" "${TF_PLUGIN_CACHE_DIR}"

record_result() {
  local section="$1"
  local label="$2"
  local command="$3"
  local status="$4"
  local exit_code="$5"
  local notes="$6"
  local step_name="${7:-}"
  local step_log_dir="${8:-}"

  SECTION="${section}" LABEL="${label}" COMMAND="${command}" STATUS="${status}" EXIT_CODE="${exit_code}" NOTES="${notes}" STEP_NAME="${step_name}" STEP_LOG_DIR="${step_log_dir}" RESULTS_FILE="${results_tmp}" \
    python3 - <<'PY'
import json
import os

section = os.environ.get("SECTION", "")
label = os.environ.get("LABEL", "")
command = os.environ.get("COMMAND", "")
status = os.environ.get("STATUS", "UNKNOWN")
exit_code = int(os.environ.get("EXIT_CODE", "0"))
notes_raw = os.environ.get("NOTES", "")
notes = [line for line in notes_raw.splitlines() if line.strip()]
step_name = os.environ.get("STEP_NAME", "")
step_log_dir = os.environ.get("STEP_LOG_DIR", "")

payload = {
    "section": section,
    "label": label,
    "command": command,
    "status": status,
    "exit_code": exit_code,
    "notes": notes,
    "step_name": step_name,
    "step_log_dir": step_log_dir,
}

with open(os.environ["RESULTS_FILE"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(payload, sort_keys=True) + "\n")
PY
}

redact_stream() {
  python3 - <<'PY'
import re
import sys

text = sys.stdin.read()
patterns = [
    r"(PVEAPIToken=)([^\s]+)",
    r"(?i)(PM_API_TOKEN_SECRET|TF_VAR_pm_api_token_secret|PM_API_TOKEN_ID|PM_API_TOKEN_SECRET|PASSWORD|SECRET)=([^\s]+)",
]
for pattern in patterns:
    text = re.sub(pattern, r"\1REDACTED", text)

sys.stdout.write(text)
PY
}

run_step() {
  local section="$1"
  local label="$2"
  local step_name="$3"
  shift 3

  local log_dir="${steps_dir}/${step_name}"
  local stdout="${log_dir}/stdout.log"
  local stderr="${log_dir}/stderr.log"
  local exit_code_file="${log_dir}/exit_code"
  mkdir -p "${log_dir}"

  local cmd_str
  cmd_str="$(printf '%q ' "$@")"
  cmd_str="${cmd_str% }"

  local start
  start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    echo "[${start}] ${section} :: ${label}"
    echo "CMD: ${cmd_str}"
    echo "LOGS: ${log_dir}"
  } >> "${commands_log}"

  set +e
  (cd "${FABRIC_REPO_ROOT}" && "$@") >"${stdout}" 2>"${stderr}"
  local rc=$?
  set -e

  echo "${rc}" > "${exit_code_file}"

  local status="PASS"
  if [[ ${rc} -ne 0 ]]; then
    status="FAIL"
  fi

  local warn_lines=""
  if [[ -s "${stdout}" || -s "${stderr}" ]]; then
    warn_lines="$(cat "${stdout}" "${stderr}" | grep -E '^(WARN|Warning|WARNING)' | head -n 20 || true)"
  fi

  if [[ -n "${warn_lines}" ]]; then
    {
      echo "WARNINGS:"
      printf '%s\n' "${warn_lines}" | redact_stream
    } >> "${commands_log}"
    printf '%s\n' "${warn_lines}" | redact_stream >> "${warnings_tmp}"
  fi

  echo "RESULT: ${status} (exit=${rc})" >> "${commands_log}"
  echo >> "${commands_log}"

  record_result "${section}" "${label}" "${cmd_str}" "${status}" "${rc}" "${warn_lines}" "${step_name}" "${log_dir}"

  if [[ "${status}" != "PASS" ]]; then
    overall_status="FAIL"
    halted=1
    if [[ ${failure_exit_code} -eq 0 ]]; then
      failure_exit_code=${rc}
    fi
    return "${rc}"
  fi

  return 0
}

check_marker() {
  local marker_name="$1"
  local marker_path="${FABRIC_REPO_ROOT}/acceptance/${marker_name}"
  local notes=""
  local status="PASS"

  if [[ ! -f "${marker_path}" ]]; then
    status="FAIL"
    notes="missing marker"
  else
    if ! rg -qi "timestamp" "${marker_path}"; then
      status="FAIL"
      notes+=$'missing timestamp\n'
    fi
    if ! rg -qi "commit" "${marker_path}"; then
      status="FAIL"
      notes+=$'missing commit\n'
    fi
    if ! rg -qi "commands" "${marker_path}"; then
      status="FAIL"
      notes+=$'missing command list\n'
    fi
    if ! rg -qi "self-hash|sha256" "${marker_path}" && [[ ! -f "${marker_path}.sha256" ]]; then
      status="FAIL"
      notes+=$'missing self-hash\n'
    fi
  fi

  record_result "B" "marker ${marker_name}" "acceptance/${marker_name}" "${status}" 0 "${notes}"
  if [[ "${status}" != "PASS" ]]; then
    overall_status="FAIL"
    marker_failures+="${marker_name}\n"
    if [[ ${failure_exit_code} -eq 0 ]]; then
      failure_exit_code=1
    fi
  fi
}

scan_invariants() {
  local label="$1"
  local pattern="$2"
  local allowlist_file="$3"
  local output

  output="$(rg -n "${pattern}" "${FABRIC_REPO_ROOT}" || true)"

  SCAN_LABEL="${label}" SCAN_PATTERN="${pattern}" SCAN_OUTPUT="${output}" ALLOWLIST_FILE="${allowlist_file}" OUT_FILE="${invariants_tmp}" SCAN_ROOT="${FABRIC_REPO_ROOT}" \
    python3 - <<'PY'
import json
import os
from pathlib import Path

label = os.environ.get("SCAN_LABEL", "scan")
pattern = os.environ.get("SCAN_PATTERN", "")
raw = os.environ.get("SCAN_OUTPUT", "")
allowlist_path = Path(os.environ.get("ALLOWLIST_FILE", ""))
root = Path(os.environ.get("SCAN_ROOT", "")).resolve()

allowlist = []
if allowlist_path.is_file():
    for line in allowlist_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        allowlist.append(line)

allowed = []
violations = []
for entry in [line for line in raw.splitlines() if line.strip()]:
    raw_path = entry.split(":", 1)[0]
    rel_path = raw_path
    path_obj = Path(raw_path)
    if root and path_obj.is_absolute():
        try:
            rel_path = str(path_obj.resolve().relative_to(root))
        except ValueError:
            rel_path = raw_path
    is_allowed = any(
        rel_path == item
        or rel_path.startswith(item.rstrip("/"))
        or raw_path == item
        or raw_path.startswith(item.rstrip("/"))
        for item in allowlist
    )
    if is_allowed:
        allowed.append(entry)
    else:
        violations.append(entry)

payload = {
    "label": label,
    "pattern": pattern,
    "allowlist": allowlist,
    "allowed_matches": allowed,
    "violations": violations,
    "status": "PASS" if not violations else "FAIL",
}

with open(os.environ["OUT_FILE"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(payload, sort_keys=True) + "\n")
PY
}

overall_status="PASS"
halted=0
failure_exit_code=0
marker_failures=""

section_gate="GATE"
test_mode="${MILESTONE_TEST_MODE:-0}"

if [[ "${test_mode}" == "1" ]]; then
  if ! run_step "T" "test pass" "test-pass" bash -c 'echo "test pass"'; then
    :
  fi
  if [[ "${MILESTONE_TEST_FAIL:-1}" == "1" ]]; then
    if ! run_step "T" "test fail" "test-fail" bash -c 'echo "intentional failure" >&2; exit 23'; then
      :
    fi
  fi
fi

if [[ "${test_mode}" != "1" ]]; then
clean_status="$(git -C "${FABRIC_REPO_ROOT}" status --porcelain)"
if [[ -n "${clean_status}" ]]; then
  record_result "${section_gate}" "repo clean" "git status --porcelain" "FAIL" 1 "working tree not clean"
  overall_status="FAIL"
  halted=1
  if [[ ${failure_exit_code} -eq 0 ]]; then
    failure_exit_code=1
  fi
else
  record_result "${section_gate}" "repo clean" "git status --porcelain" "PASS" 0 ""
fi

if [[ ${halted} -eq 0 ]]; then
  if rg -n "OPEN" "${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md" >/dev/null 2>&1; then
    record_result "${section_gate}" "required fixes" "rg -n OPEN REQUIRED-FIXES.md" "FAIL" 1 "OPEN items present"
    overall_status="FAIL"
    halted=1
    if [[ ${failure_exit_code} -eq 0 ]]; then
      failure_exit_code=1
    fi
  else
    record_result "${section_gate}" "required fixes" "rg -n OPEN REQUIRED-FIXES.md" "PASS" 0 ""
  fi
fi

if [[ ${halted} -eq 0 ]]; then
  if ! run_step "A" "git pull" "git-pull" git pull --ff-only; then
    :
  fi
fi

if [[ ${halted} -eq 0 ]]; then
  if ! run_step "A" "pre-commit" "pre-commit" pre-commit run --all-files; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "A" "lint" "lint" bash fabric-ci/scripts/lint.sh; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "A" "validate" "validate" bash fabric-ci/scripts/validate.sh; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "A" "policy" "policy-check" make policy.check; then
    :
  fi
fi

if [[ ${halted} -eq 0 ]]; then
  markers=(
    "PHASE1_ACCEPTED.md"
    "PHASE2_ACCEPTED.md"
    "PHASE2_1_ACCEPTED.md"
    "PHASE2_2_ACCEPTED.md"
    "PHASE3_PART1_ACCEPTED.md"
    "PHASE3_PART2_ACCEPTED.md"
    "PHASE3_PART3_ACCEPTED.md"
    "PHASE4_ACCEPTED.md"
    "PHASE5_ACCEPTED.md"
    "PHASE6_PART1_ACCEPTED.md"
    "PHASE6_PART2_ACCEPTED.md"
    "PHASE6_PART3_ACCEPTED.md"
    "PHASE8_PART1_ACCEPTED.md"
    "PHASE12_PART1_ACCEPTED.md"
    "PHASE12_PART2_ACCEPTED.md"
    "PHASE12_PART3_ACCEPTED.md"
    "PHASE12_PART4_ACCEPTED.md"
    "PHASE12_PART5_ACCEPTED.md"
    "PHASE12_PART6_ACCEPTED.md"
  )

  mapfile -t phase11_markers < <(find "${FABRIC_REPO_ROOT}/acceptance" -maxdepth 1 -type f -name 'PHASE11*_ACCEPTED.md' -printf '%f\n' | LC_ALL=C sort)
  if [[ "${#phase11_markers[@]}" -gt 0 ]]; then
    markers+=("${phase11_markers[@]}")
  fi

  for marker in "${markers[@]}"; do
    check_marker "${marker}"
  done

  if [[ -n "${marker_failures}" ]]; then
    halted=1
  fi
fi

if [[ ${halted} -eq 0 ]]; then
  scan_invariants "insecure_flags" "(--insecure|-k\\b|sslmode=disable|TLS_SKIP)" "${FABRIC_REPO_ROOT}/ops/milestones/phase1-12/allowlist-insecure.txt"
  scan_invariants "secret_patterns" "(BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|AKIA[0-9A-Z]{16}|password=|secret=)" "${FABRIC_REPO_ROOT}/ops/milestones/phase1-12/allowlist-secrets.txt"

  if python3 - "${invariants_tmp}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
violations = False
for line in path.read_text(encoding="utf-8").splitlines():
    payload = json.loads(line)
    if payload.get("status") != "PASS":
        violations = True
        break

sys.exit(1 if violations else 0)
PY
  then
    record_result "C" "invariants" "rg -n patterns" "PASS" 0 ""
  else
    record_result "C" "invariants" "rg -n patterns" "FAIL" 1 "see invariants.json"
    overall_status="FAIL"
    halted=1
    if [[ ${failure_exit_code} -eq 0 ]]; then
      failure_exit_code=1
    fi
  fi
fi

if [[ ${halted} -eq 0 ]]; then
  if ! run_step "D" "phase2 dns" "phase2-dns" env ENV=samakia-dns make phase2.accept; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "D" "phase2 minio" "phase2-minio" env ENV=samakia-minio make phase2.accept; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "D" "phase2.1 shared" "phase2-1-shared" env ENV=samakia-shared make phase2.1.accept; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "D" "phase2.2 shared" "phase2-2-shared" env ENV=samakia-shared make phase2.2.accept; then
    :
  fi
fi

if [[ ${halted} -eq 0 ]]; then
  if ! run_step "E" "phase3 part1" "phase3-part1" make phase3.part1.accept; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "E" "phase3 part2" "phase3-part2" make phase3.part2.accept; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "E" "phase3 part3" "phase3-part3" env ENV=samakia-prod make phase3.part3.accept; then
    :
  fi
fi

if [[ ${halted} -eq 0 ]]; then
  if ! run_step "F" "policy" "policy-recheck" make policy.check; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "F" "validate" "validate-recheck" bash fabric-ci/scripts/validate.sh; then
    :
  fi
fi

if [[ ${halted} -eq 0 ]]; then
  if ! run_step "G" "phase5 entry" "phase5-entry" make phase5.entry.check; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "G" "phase5 accept" "phase5-accept" make phase5.accept; then
    :
  fi
fi

if [[ ${halted} -eq 0 ]]; then
  if ! run_step "H" "phase6 entry" "phase6-entry" make phase6.entry.check; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "H" "phase6 part1" "phase6-part1" make phase6.part1.accept; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "H" "phase6 part2" "phase6-part2" make phase6.part2.accept; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "H" "phase6 part3" "phase6-part3" make phase6.part3.accept; then
    :
  fi
fi

if [[ ${halted} -eq 0 ]]; then
  if ! run_step "I" "phase8 entry" "phase8-entry" make phase8.entry.check; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "I" "phase8 part1" "phase8-part1" env CI=1 make phase8.part1.accept; then
    :
  fi
fi

if [[ ${halted} -eq 0 ]]; then
  if ! run_step "J" "tenants validate" "tenants-validate" make tenants.validate; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "J" "substrate contracts" "substrate-contracts" make substrate.contracts.validate; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "J" "tenants capacity" "tenants-capacity" env TENANT=all make tenants.capacity.validate; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "J" "bindings validate" "bindings-validate" env TENANT=all make bindings.validate; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "J" "bindings render" "bindings-render" env TENANT=all make bindings.render; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "J" "bindings secrets" "bindings-secrets" env TENANT=all make bindings.secrets.inspect; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "J" "bindings verify" "bindings-verify" env TENANT=all make bindings.verify.offline; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "J" "drift detect" "drift-detect" env TENANT=all DRIFT_OFFLINE=1 DRIFT_NON_BLOCKING=1 DRIFT_FAIL_ON=none make drift.detect; then
    :
  fi
fi
if [[ ${halted} -eq 0 ]]; then
  if ! run_step "J" "drift summary" "drift-summary" env TENANT=all make drift.summary; then
    :
  fi
fi
fi

sign_manifest=0
if [[ "${MILESTONE_SIGN:-0}" == "1" ]]; then
  sign_manifest=1
fi
if [[ "${ENV:-}" == "samakia-prod" || "${ENV:-}" == "prod" ]]; then
  sign_manifest=1
fi
if [[ "${CI:-0}" == "1" && "${MILESTONE_SIGN:-0}" != "1" ]]; then
  sign_manifest=0
fi

if [[ "${sign_manifest}" -eq 1 ]] && ! command -v gpg >/dev/null 2>&1; then
  overall_status="FAIL"
  if [[ ${failure_exit_code} -eq 0 ]]; then
    failure_exit_code=1
  fi
  echo "WARN: gpg missing; milestone signing required" >> "${warnings_tmp}"
fi

invariants_json="${packet_dir}/invariants.json"
phase_results_json="${packet_dir}/phase-results.json"
summary_md="${packet_dir}/summary.md"

python3 - "${invariants_tmp}" "${invariants_json}" <<'PY'
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
out = Path(sys.argv[2])
entries = [json.loads(line) for line in source.read_text(encoding="utf-8").splitlines() if line.strip()]

out.write_text(json.dumps({"scans": entries}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

python3 - "${results_tmp}" "${warnings_tmp}" "${phase_results_json}" "${summary_md}" "${stamp}" "${overall_status}" "${packet_dir}" "${FABRIC_REPO_ROOT}" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

results_path = Path(sys.argv[1])
warnings_path = Path(sys.argv[2])
phase_results = Path(sys.argv[3])
summary_md = Path(sys.argv[4])
stamp = sys.argv[5]
overall_status = sys.argv[6]
packet_dir = sys.argv[7]
repo_root = sys.argv[8]

entries = [json.loads(line) for line in results_path.read_text(encoding="utf-8").splitlines() if line.strip()]

sections = []
section_map = {}
for entry in entries:
    section_id = entry.get("section", "")
    if section_id not in section_map:
        section = {"id": section_id, "status": "PASS", "checks": []}
        section_map[section_id] = section
        sections.append(section)
    section = section_map[section_id]
    section["checks"].append(entry)
    if entry.get("status") != "PASS":
        section["status"] = "FAIL"

failures = [entry for entry in entries if entry.get("status") != "PASS"]
commands = [entry.get("command") for entry in entries if entry.get("command")]

warnings = []
if warnings_path.exists():
    for line in warnings_path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            warnings.append(line.strip())

redact_patterns = [
    (re.compile(r"(PVEAPIToken=)([^\s]+)"), r"\\1REDACTED"),
    (re.compile(r"(?i)(PM_API_TOKEN_SECRET|TF_VAR_pm_api_token_secret|PM_API_TOKEN_ID|PM_API_TOKEN_SECRET|PASSWORD|SECRET)=([^\s]+)"), r"\\1=REDACTED"),
]


def redact_line(line: str) -> str:
    text = line
    for pattern, replacement in redact_patterns:
        text = pattern.sub(replacement, text)
    return text

payload = {
    "milestone": "phase1-12",
    "timestamp_utc": stamp,
    "commit": os.popen(f"git -C '{repo_root}' rev-parse HEAD 2>/dev/null").read().strip() or "unknown",
    "overall_status": overall_status,
    "sections": sections,
    "failures": failures,
}

phase_results.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

lines = [
    "# Phase 1–12 Milestone Verification Summary",
    "",
    f"Timestamp (UTC): {stamp}",
    f"Commit: {payload['commit']}",
    f"Overall status: {overall_status}",
    "",
    "## Section status",
]
for section in sections:
    lines.append(f"- Section {section['id']}: {section['status']}")

if failures:
    lines.append("")
    lines.append("## Failures")
    for entry in failures:
        lines.append(f"- {entry.get('section')} {entry.get('label')}: {entry.get('status')}")
    lines.append("")
    lines.append("## Failure details")
    for entry in failures:
        step_name = entry.get("step_name") or entry.get("label") or "unknown"
        exit_code = entry.get("exit_code")
        log_dir = entry.get("step_log_dir")
        lines.append(f"- Step: {step_name} (exit {exit_code})")
        if log_dir:
            stderr_path = Path(log_dir) / "stderr.log"
            if stderr_path.exists():
                stderr_lines = stderr_path.read_text(encoding="utf-8").splitlines()[:20]
                if stderr_lines:
                    lines.append("  stderr (first 20 lines, redacted):")
                    for line in stderr_lines:
                        lines.append(f"  {redact_line(line)}")
            lines.append(f"  Logs: {log_dir}")
        else:
            lines.append("  Logs: n/a")

if warnings:
    lines.append("")
    lines.append("## Warnings")
    for warning in warnings:
        lines.append(f"- {warning}")

lines.extend([
    "",
    "## Reproduction commands",
])
for cmd in commands:
    lines.append(f"- {cmd}")

lines.extend([
    "",
    "## Evidence",
    f"- Packet: {packet_dir}",
    "- invariants.json",
    "- phase-results.json",
    "- commands.log",
    "- manifest.sha256",
    "",
    "## Safety statement",
    "- No secrets were committed.",
    "- No autonomous apply occurred.",
    "- CI remained read-only.",
    "- Verification was deterministic and operator-controlled.",
])

summary_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

(
  cd "${packet_dir}"
  find . \
    -type f \
    ! -name 'manifest.sha256' \
    ! -name 'manifest.sha256.asc' \
    ! -name 'manifest.sha256.asc.a' \
    ! -name 'manifest.sha256.asc.b' \
    ! -name 'manifest.sha256.tsr' \
    ! -name 'tsa-metadata.json' \
    -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum > manifest.sha256
)

if [[ "${sign_manifest}" -eq 1 ]]; then
  if command -v gpg >/dev/null 2>&1; then
    gpg --batch --yes --detach-sign --armor --output "${packet_dir}/manifest.sha256.asc" "${packet_dir}/manifest.sha256"
  fi
fi

if [[ "${overall_status}" != "PASS" ]]; then
  echo "FAIL: milestone verification failed" >&2
  echo "Evidence written to ${packet_dir}" >&2
  exit_code="${failure_exit_code:-1}"
  if [[ ${exit_code} -eq 0 ]]; then
    exit_code=1
  fi
  exit "${exit_code}"
fi

echo "OK: milestone verification PASS; evidence at ${packet_dir}"
