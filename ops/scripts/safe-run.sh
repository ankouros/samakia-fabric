#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat >&2 <<'EOT'
Usage:
  safe-run.sh <name> [--dry-run|--execute]

Runs an allowlisted 03:00-safe command from ops/scripts/safe-index.yml.
Default is execute for read-only entries. Use --dry-run to print only.
Execute mode requires SAFE_RUN_EXECUTE=1 and I_UNDERSTAND_MUTATION=1.
EOT
}

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

name="${1:-}"
shift $(( $# >= 1 ? 1 : $# ))

if [[ -z "${name}" ]]; then
  usage
  exit 2
fi

mode="run"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      mode="dry-run"
      shift
      ;;
    --execute)
      mode="execute"
      shift
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
require_cmd git
require_cmd python3
require_cmd sha256sum
require_cmd find
require_cmd sort
require_cmd xargs

index_path="${FABRIC_REPO_ROOT}/ops/scripts/safe-index.yml"
if [[ ! -f "${index_path}" ]]; then
  echo "ERROR: safe index not found: ${index_path}" >&2
  exit 1
fi

mapfile -t entry_lines < <(python3 - "${index_path}" "${name}" <<'PY'
import json
import sys
from pathlib import Path

index_path, name = sys.argv[1:3]

try:
    data = json.loads(Path(index_path).read_text())
except Exception as exc:
    print(f"ERROR: cannot parse safe-index: {exc}", file=sys.stderr)
    sys.exit(2)

for item in data.get("allowlist", []):
    if item.get("name") == name:
        cmd = item.get("command")
        entry_type = item.get("type")
        if not cmd or not entry_type:
            print("ERROR: safe-index entry missing command/type", file=sys.stderr)
            sys.exit(2)
        print(entry_type)
        print(cmd)
        sys.exit(0)

print("ERROR: allowlist entry not found", file=sys.stderr)
sys.exit(1)
PY
)

entry_type="${entry_lines[0]:-}"
entry_command="${entry_lines[1]:-}"

if [[ -z "${entry_type}" || -z "${entry_command}" ]]; then
  echo "ERROR: failed to resolve safe-run entry" >&2
  exit 1
fi

if [[ "${entry_type}" == "execute-guarded" && "${mode}" != "execute" ]]; then
  echo "ERROR: ${name} requires --execute mode" >&2
  exit 1
fi

if [[ "${mode}" == "execute" ]]; then
  if [[ "${SAFE_RUN_EXECUTE:-}" != "1" ]]; then
    echo "ERROR: SAFE_RUN_EXECUTE must be set to 1 for execute mode" >&2
    exit 1
  fi
  if [[ "${I_UNDERSTAND_MUTATION:-}" != "1" ]]; then
    echo "ERROR: I_UNDERSTAND_MUTATION must be set to 1 for execute mode" >&2
    exit 1
  fi
  if [[ "${entry_type}" == "read-only" ]]; then
    echo "ERROR: ${name} is read-only; execute mode is not allowed" >&2
    exit 1
  fi
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
commit_short="$(git -C "${FABRIC_REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

evidence_dir="${FABRIC_REPO_ROOT}/evidence/ai/safe-run/${name}/${stamp}"
mkdir -p "${evidence_dir}"

meta_path="${evidence_dir}/metadata.json"
exec_log="${evidence_dir}/execution.log"
manifest_path="${evidence_dir}/manifest.sha256"

cat <<EOF_META >"${meta_path}"
{
  "name": "${name}",
  "mode": "${mode}",
  "command": "${entry_command}",
  "timestamp_utc": "${stamp}",
  "commit_short": "${commit_short}"
}
EOF_META

cmd_line="cd ${FABRIC_REPO_ROOT} && ${entry_command}"

if [[ "${mode}" == "dry-run" ]]; then
  echo "DRY-RUN: ${cmd_line}" >"${exec_log}"
else
  bash -lc "${cmd_line}" >"${exec_log}" 2>&1
fi

(
  cd "${evidence_dir}"
  find . -type f ! -name 'manifest.sha256' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >"${manifest_path}"
)

echo "OK: safe-run evidence written to ${evidence_dir}"
