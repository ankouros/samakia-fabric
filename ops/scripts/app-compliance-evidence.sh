#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage:
  app-compliance-evidence.sh <env> <service_name> <service_root_dir> [--config <paths.txt>] [--profile <path>] [--version <string>]

Creates a deterministic, read-only evidence bundle under:
  compliance/<env>/app-evidence-<service_name>/snapshot-<UTC>/

Evidence is NOT signed by this script. Use the existing signing workflow:
  COMPLIANCE_SNAPSHOT_DIR=... bash ops/scripts/compliance-snapshot.sh <env>

Options:
  --config <paths.txt>   Newline-separated relative paths (from service_root_dir) to fingerprint.
  --profile <path>       Service compliance profile file (recommended, docs-only; must not contain secrets).
  --version <string>     Service version/build identifier (if available).

Hard rules:
  - Refuses secret-like files by filename patterns and by content markers.
  - Hashes files; does not copy file contents into the evidence bundle.
EOF
}

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: file not found: ${path}" >&2
    exit 1
  fi
}

ENV_NAME="${1:-}"
SERVICE_NAME="${2:-}"
SERVICE_ROOT="${3:-}"
shift $(( $# >= 3 ? 3 : $# ))

if [[ -z "${ENV_NAME}" || -z "${SERVICE_NAME}" || -z "${SERVICE_ROOT}" ]]; then
  usage
  exit 2
fi

SERVICE_ROOT="$(cd "${SERVICE_ROOT}" && pwd)"

require_cmd git
require_cmd sha256sum
require_cmd python3
require_cmd find
require_cmd sort
require_cmd xargs
require_cmd awk
require_cmd sed
require_cmd head
require_cmd date

CONFIG_LIST=""
PROFILE_PATH=""
SERVICE_VERSION="unknown"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_LIST="${2:-}"
      shift 2
      ;;
    --profile)
      PROFILE_PATH="${2:-}"
      shift 2
      ;;
    --version)
      SERVICE_VERSION="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

timestamp_utc="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="${REPO_ROOT}/compliance/${ENV_NAME}/app-evidence-${SERVICE_NAME}/snapshot-${timestamp_utc}"
mkdir -p "${out_dir}"

deny_path_regex='(^|/)(\\.env(\\..*)?$|.*\\.(pem|key|p12|pfx)$|terraform\\.tfvars(\\..*)?$|.*tfstate(\\..*)?$|id_rsa(\\.pub)?$|id_ed25519(\\.pub)?$|.*secrets?.*|.*vault.*)$'

is_denylisted_path() {
  local rel="$1"
  if [[ "${rel}" =~ ${deny_path_regex} ]]; then
    # Allow example env files explicitly.
    if [[ "${rel}" == ".env.example" || "${rel}" == */.env.example ]]; then
      return 1
    fi
    return 0
  fi
  return 1
}

contains_secret_markers() {
  local path="$1"
  python3 - "${path}" <<'PY' >/dev/null
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_bytes()

if re.search(rb"BEGIN (OPENSSH )?PRIVATE KEY|OPENSSH PRIVATE KEY|PRIVATE KEY-----", data):
    sys.exit(0)

text = data.decode("utf-8", errors="ignore")

def looks_like_secret_value(value: str) -> bool:
    v = value.strip().strip('"').strip("'")
    if v == "" or v.lower() in {"changeme", "redacted", "example", "dummy"}:
        return False
    if v.startswith("${") or v.startswith("$") or "{{" in v:
        return False
    if v.startswith("<") or v.startswith("[") or v.startswith("("):
        return False
    if "REDACTED" in v.upper() or "CHANGEME" in v.upper():
        return False
    return True

for line in text.splitlines():
    m = re.search(r"(?i)\\b(password|passwd|token|secret|api_key)\\b\\s*[:=]\\s*(.+)$", line)
    if not m:
        continue
    if looks_like_secret_value(m.group(2)):
        sys.exit(0)

sys.exit(1)
PY
}

config_fingerprint_txt="${out_dir}/config-fingerprint.txt"
runtime_checks_txt="${out_dir}/runtime-checks.txt"
versions_txt="${out_dir}/versions.txt"
references_txt="${out_dir}/references.txt"
metadata_json="${out_dir}/metadata.json"

repo_commit="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
repo_commit_short="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
repo_dirty="false"
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain=v1 2>/dev/null || true)" ]]; then
  repo_dirty="true"
fi

service_commit="$(git -C "${SERVICE_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
service_commit_short="$(git -C "${SERVICE_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
service_dirty="false"
if [[ -n "$(git -C "${SERVICE_ROOT}" status --porcelain=v1 2>/dev/null || true)" ]]; then
  service_dirty="true"
fi

service_root_for_metadata="${SERVICE_ROOT}"
if [[ "${SERVICE_ROOT}" == "${REPO_ROOT}/"* ]]; then
  service_root_for_metadata="${SERVICE_ROOT#"${REPO_ROOT}/"}"
fi

{
  echo "timestamp_utc=${timestamp_utc}"
  echo "environment=${ENV_NAME}"
  echo "service_name=${SERVICE_NAME}"
  echo
  echo "repo_commit=${repo_commit}"
  echo "repo_dirty=${repo_dirty}"
  echo "service_commit=${service_commit}"
  echo "service_dirty=${service_dirty}"
  echo
  echo "tool_versions:"
  git --version || true
  sha256sum --version | head -n 1 || true
  python3 --version || true
} >"${versions_txt}"

{
  echo "# References (optional)"
  echo
  echo "# Add ticket IDs / scan report IDs / runbook paths here."
  echo "# No secrets, no credentials."
} >"${references_txt}"

{
  echo "# Runtime checks (read-only)"
  echo
  echo "NOT_RUN: This helper does not SSH into targets by default."
  echo "Guidance: collect runtime evidence separately (e.g. service version, OS release, log sinks) and attach sanitized outputs as additional files if needed."
} >"${runtime_checks_txt}"

touch "${config_fingerprint_txt}"

inputs_json="[]"

if [[ -n "${PROFILE_PATH}" ]]; then
  profile_abs="${PROFILE_PATH}"
  if [[ "${PROFILE_PATH}" != /* ]]; then
    profile_abs="${SERVICE_ROOT}/${PROFILE_PATH}"
  fi

  if [[ ! -f "${profile_abs}" ]]; then
    echo "ERROR: profile file not found: ${PROFILE_PATH} (${profile_abs})" >&2
    exit 1
  fi

  profile_rel="${PROFILE_PATH}"
  if [[ "${PROFILE_PATH}" == /* && "${PROFILE_PATH}" == "${SERVICE_ROOT}/"* ]]; then
    profile_rel="${PROFILE_PATH#"${SERVICE_ROOT}/"}"
  fi

  if is_denylisted_path "${profile_rel}"; then
    echo "ERROR: denylisted profile path (refusing to hash): ${profile_rel}" >&2
    exit 1
  fi

  if contains_secret_markers "${profile_abs}"; then
    echo "ERROR: secret markers detected in profile (refusing evidence): ${profile_rel}" >&2
    exit 1
  fi

  profile_sha="$(sha256sum "${profile_abs}" | awk '{print $1}')"
  printf '%s  %s\n' "${profile_sha}" "${profile_rel}" >>"${config_fingerprint_txt}"
  inputs_json="$(
    python3 - "${inputs_json}" "${profile_rel}" "${profile_sha}" <<'PY'
import json
import sys

arr = json.loads(sys.argv[1])
arr.append({"path": sys.argv[2], "sha256": sys.argv[3], "type": "profile"})
print(json.dumps(arr))
PY
  )"
fi

if [[ -n "${CONFIG_LIST}" ]]; then
  require_file "${CONFIG_LIST}"

  while IFS= read -r rel || [[ -n "${rel}" ]]; do
    rel="$(echo "${rel}" | sed 's/#.*$//' | xargs || true)"
    [[ -z "${rel}" ]] && continue

    if is_denylisted_path "${rel}"; then
      echo "ERROR: denylisted config path (refusing to hash): ${rel}" >&2
      exit 1
    fi

    abs="${SERVICE_ROOT}/${rel}"
    if [[ ! -f "${abs}" ]]; then
      echo "ERROR: config file does not exist: ${rel} (${abs})" >&2
      exit 1
    fi

    if contains_secret_markers "${abs}"; then
      echo "ERROR: secret markers detected in file (refusing evidence): ${rel}" >&2
      echo "Hint: create a redacted evidence export and hash that instead." >&2
      exit 1
    fi

    sha="$(sha256sum "${abs}" | awk '{print $1}')"
    printf '%s  %s\n' "${sha}" "${rel}" >>"${config_fingerprint_txt}"

    inputs_json="$(
      python3 - "${inputs_json}" "${rel}" "${sha}" <<'PY'
import json
import sys

arr = json.loads(sys.argv[1])
rel = sys.argv[2]
sha = sys.argv[3]
arr.append({"path": rel, "sha256": sha})
print(json.dumps(arr))
PY
    )"
  done <"${CONFIG_LIST}"
else
  printf '%s\n' "# No config files provided. Provide --config paths.txt to fingerprint allowlisted files." >>"${config_fingerprint_txt}"
fi

export E_TS="${timestamp_utc}"
export E_ENV="${ENV_NAME}"
export E_SVC="${SERVICE_NAME}"
export E_ROOT="${service_root_for_metadata}"
export E_SVC_COMMIT="${service_commit}"
export E_SVC_COMMIT_SHORT="${service_commit_short}"
export E_SVC_DIRTY="${service_dirty}"
export E_REPO_COMMIT="${repo_commit}"
export E_REPO_COMMIT_SHORT="${repo_commit_short}"
export E_REPO_DIRTY="${repo_dirty}"
export E_INPUTS_JSON="${inputs_json}"
export E_VERSION="${SERVICE_VERSION}"

python3 - "${metadata_json}" <<'PY'
import json
import os
import sys

out = sys.argv[1]

doc = {
  "timestamp_utc": os.environ["E_TS"],
  "environment": os.environ["E_ENV"],
  "service": {
    "name": os.environ["E_SVC"],
    "root_dir": os.environ["E_ROOT"],
    "git_commit": os.environ["E_SVC_COMMIT"],
    "git_commit_short": os.environ["E_SVC_COMMIT_SHORT"],
    "git_dirty": os.environ["E_SVC_DIRTY"] == "true",
    "version": os.environ.get("E_VERSION") or "unknown",
  },
  "repository": {
    "git_commit": os.environ["E_REPO_COMMIT"],
    "git_commit_short": os.environ["E_REPO_COMMIT_SHORT"],
    "git_dirty": os.environ["E_REPO_DIRTY"] == "true",
  },
  "inputs": json.loads(os.environ["E_INPUTS_JSON"]),
}

with open(out, "w", encoding="utf-8") as f:
  json.dump(doc, f, indent=2, sort_keys=True)
  f.write("\\n")
PY

manifest="${out_dir}/manifest.sha256"
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
    | xargs -0 sha256sum >"${manifest}"
)

echo "OK: wrote application evidence bundle: ${out_dir}"
echo "Next: sign it via:"
echo "  COMPLIANCE_SNAPSHOT_DIR=\"${out_dir}\" bash ops/scripts/compliance-snapshot.sh ${ENV_NAME}"

exit 0
