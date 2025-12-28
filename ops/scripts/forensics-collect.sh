#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage:
  forensics-collect.sh <incident-id> [--env <env>] [--scope <scope>] [--target <name>] [--out <dir>] [--authorize <text>] [--include-auth-logs]

Creates a read-only evidence bundle under:
  forensics/<incident-id>/snapshot-<UTC>/

Default behavior is conservative:
  - collects system identity, process/user context, network state, package list
  - collects minimal SSH/sudo auth logs only when --include-auth-logs is set
  - hashes a safe set of critical files (no secrets)

This script does NOT sign. To sign/notarize, reuse the existing workflow:
  COMPLIANCE_SNAPSHOT_DIR="forensics/<incident-id>/snapshot-<UTC>" bash ops/scripts/compliance-snapshot.sh <env>
EOF
}

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

INCIDENT_ID="${1:-}"
shift $(( $# >= 1 ? 1 : $# ))

if [[ -z "${INCIDENT_ID}" ]]; then
  usage
  exit 2
fi

ENV_NAME="${FORENSICS_ENV:-}"
SCOPE="${FORENSICS_SCOPE:-lxc}"
TARGET="${FORENSICS_TARGET:-$(hostname 2>/dev/null || echo unknown)}"
OUT_DIR=""
AUTHZ="${FORENSICS_AUTHORIZATION:-}"
INCLUDE_AUTH_LOGS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_NAME="${2:-}"
      shift 2
      ;;
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --authorize)
      AUTHZ="${2:-}"
      shift 2
      ;;
    --out)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --include-auth-logs)
      INCLUDE_AUTH_LOGS=1
      shift 1
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

require_cmd date
require_cmd uname
require_cmd id
require_cmd ps
require_cmd ip
require_cmd sha256sum
require_cmd find
require_cmd sort
require_cmd xargs
require_cmd awk
require_cmd python3

timestamp_utc="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ -z "${OUT_DIR}" ]]; then
  OUT_DIR="${REPO_ROOT}/forensics/${INCIDENT_ID}/snapshot-${timestamp_utc}"
fi
mkdir -p "${OUT_DIR}"/{system,network,logs,packages,integrity,apps}

capture_cmd() {
  local out_file="$1"
  shift
  {
    echo "command: $*"
    echo "timestamp_utc: ${timestamp_utc}"
    echo "exit_code: (captured below)"
    echo
    set +e
    "$@"
    rc=$?
    set -e
    echo
    echo "exit_code: ${rc}"
  } >"${out_file}" 2>&1
}

hash_file_if_safe() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    return 0
  fi

  case "${path}" in
    /etc/shadow|/etc/gshadow|/root/*|/home/*/.ssh/*|/etc/ssh/ssh_host_*key)
      return 0
      ;;
  esac

  python3 - "${path}" <<'PY' >/dev/null
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_bytes()

if re.search(rb"BEGIN (OPENSSH )?PRIVATE KEY|OPENSSH PRIVATE KEY|PRIVATE KEY-----", data):
    sys.exit(1)

text = data.decode("utf-8", errors="ignore")
for line in text.splitlines():
    if re.search(r"(?i)\\b(password|token|secret|api_key)\\b\\s*[:=]", line):
        sys.exit(1)
sys.exit(0)
PY
}

{
  echo "# Timeline (manual notes)"
  echo
  echo "- incident_id: ${INCIDENT_ID}"
  echo "- snapshot_utc: ${timestamp_utc}"
  echo "- collector: $(id -un 2>/dev/null || echo unknown)"
  echo "- target: ${TARGET}"
  echo "- env: ${ENV_NAME:-unknown}"
  echo "- scope: ${SCOPE}"
  echo
  echo "Add observations here without editing collected artifacts."
} >"${OUT_DIR}/timeline.txt"

collector="$(id -un 2>/dev/null || echo unknown)"
collector_uid="$(id -u 2>/dev/null || echo unknown)"

export F_INCIDENT_ID="${INCIDENT_ID}"
export F_TIMESTAMP="${timestamp_utc}"
export F_COLLECTOR="${collector}"
export F_COLLECTOR_UID="${collector_uid}"
export F_ENV="${ENV_NAME:-unknown}"
export F_SCOPE="${SCOPE}"
export F_TARGET="${TARGET}"
export F_AUTHZ="${AUTHZ}"

python3 - "${OUT_DIR}/metadata.json" <<'PY'
import json
import os
import sys

out = sys.argv[1]

doc = {
  "incident_id": os.environ["F_INCIDENT_ID"],
  "timestamp_utc": os.environ["F_TIMESTAMP"],
  "collector": {
    "user": os.environ["F_COLLECTOR"],
    "uid": os.environ["F_COLLECTOR_UID"],
  },
  "environment": os.environ["F_ENV"],
  "scope": os.environ["F_SCOPE"],
  "targets": [os.environ["F_TARGET"]],
  "authorization": os.environ["F_AUTHZ"] or None,
  "hashing": {"algorithm": "sha256"},
  "redaction_policy": {
    "excluded": [
      "/etc/shadow",
      "/root/*",
      "/home/*/.ssh/*",
      "/etc/ssh/ssh_host_*key",
    ]
  },
}

with open(out, "w", encoding="utf-8") as f:
  json.dump(doc, f, indent=2, sort_keys=True)
  f.write("\n")
PY

# System
capture_cmd "${OUT_DIR}/system/identity.txt" bash -lc 'hostname; date -u; uptime || true; cat /etc/os-release 2>/dev/null || true; uname -a'
capture_cmd "${OUT_DIR}/system/users.txt" bash -lc 'id; who -a 2>/dev/null || true; w 2>/dev/null || true'
capture_cmd "${OUT_DIR}/system/processes.txt" bash -lc 'ps auxww'

# Network
capture_cmd "${OUT_DIR}/network/interfaces.txt" bash -lc 'ip a'
capture_cmd "${OUT_DIR}/network/routes.txt" bash -lc 'ip r'
capture_cmd "${OUT_DIR}/network/sockets.txt" bash -lc 'ss -tulpen 2>/dev/null || ss -tulpn 2>/dev/null || ss -tulp 2>/dev/null || true'

# Packages
capture_cmd "${OUT_DIR}/packages/dpkg.txt" bash -lc 'dpkg -l 2>/dev/null || true'
capture_cmd "${OUT_DIR}/packages/apt-security.txt" bash -lc 'unattended-upgrades --dry-run --debug 2>/dev/null || true'

# Logs (opt-in)
if [[ "${INCLUDE_AUTH_LOGS}" -eq 1 ]]; then
  if command -v journalctl >/dev/null 2>&1; then
    capture_cmd "${OUT_DIR}/logs/journal-ssh.txt" bash -lc 'journalctl --no-pager -u ssh -n 500 2>/dev/null || true'
    capture_cmd "${OUT_DIR}/logs/journal-sudo.txt" bash -lc 'journalctl --no-pager _COMM=sudo -n 200 2>/dev/null || true'
  fi
  if [[ -f /var/log/auth.log ]]; then
    capture_cmd "${OUT_DIR}/logs/auth-log-tail.txt" bash -lc 'tail -n 500 /var/log/auth.log 2>/dev/null || true'
  fi
fi

# Integrity hashes (safe subset)
hashes="${OUT_DIR}/integrity/hashes.txt"
touch "${hashes}"
for f in /etc/ssh/sshd_config /etc/passwd /etc/group /etc/sudoers; do
  if hash_file_if_safe "${f}"; then
    sha="$(sha256sum "${f}" | awk '{print $1}')"
    printf '%s  %s\n' "${sha}" "${f}" >>"${hashes}"
  fi
done
if [[ -d /etc/sudoers.d ]]; then
  while IFS= read -r -d '' f; do
    if hash_file_if_safe "${f}"; then
      sha="$(sha256sum "${f}" | awk '{print $1}')"
      printf '%s  %s\n' "${sha}" "${f}" >>"${hashes}"
    fi
  done < <(find /etc/sudoers.d -type f -print0 2>/dev/null || true)
fi

# Evidence manifest (hashes of evidence files)
(
  cd "${OUT_DIR}"
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

echo "OK: wrote forensics evidence bundle: ${OUT_DIR}"
echo "Next (optional): sign/notarize it via:"
echo "  COMPLIANCE_SNAPSHOT_DIR=\"${OUT_DIR}\" bash ops/scripts/compliance-snapshot.sh ${ENV_NAME:-<env>}"
