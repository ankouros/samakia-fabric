#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

entry=""
mode="offline"
secret_file=""
ca_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --entry)
      entry="$2"
      shift 2
      ;;
    --mode)
      mode="$2"
      shift 2
      ;;
    --secret)
      secret_file="$2"
      shift 2
      ;;
    --ca-file)
      ca_file="$2"
      shift 2
      ;;
    *)
      echo "usage: qdrant.sh --entry <json> [--mode offline|live] [--secret <file>] [--ca-file <path>]" >&2
      exit 2
      ;;
  esac
 done

if [[ -z "${entry}" ]]; then
  echo "ERROR: --entry is required" >&2
  exit 2
fi

if [[ "${mode}" == "offline" ]]; then
  python3 - <<'PY'
import json
print(json.dumps({"check": "qdrant", "status": "PASS", "mode": "offline", "message": "offline mode: probe skipped"}, sort_keys=True))
PY
  exit 0
fi

if [[ -z "${secret_file}" || ! -f "${secret_file}" ]]; then
  echo "ERROR: secret file required for live qdrant probe" >&2
  exit 2
fi

python3 - "${entry}" "${secret_file}" "${ca_file}" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

entry_path = Path(sys.argv[1])
secret_path = Path(sys.argv[2])
ca_path = Path(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] else None

entry = json.loads(entry_path.read_text())
endpoint = entry.get("endpoint", {})
resources = entry.get("resources", {})
secret = json.loads(secret_path.read_text())

api_key = secret.get("api_key") or secret.get("token") or ""

host = endpoint.get("host")
port = endpoint.get("port")
protocol = endpoint.get("protocol") or "https"
if not host or not port:
    print(json.dumps({"check": "qdrant", "status": "FAIL", "message": "missing endpoint host/port"}, sort_keys=True))
    sys.exit(1)

headers = []
if api_key:
    headers.extend(["-H", f"api-key: {api_key}"])

base = f"{protocol}://{host}:{port}"
cmd = ["curl", "--silent", "--show-error", "--fail", "--connect-timeout", "5", "--max-time", "10"]
if ca_path and ca_path.exists():
    cmd.extend(["--cacert", str(ca_path)])
cmd.extend(headers)

try:
    output = subprocess.check_output(cmd + [f"{base}/collections"], stderr=subprocess.STDOUT, timeout=15)
    data = json.loads(output.decode())
except subprocess.CalledProcessError as exc:
    msg = exc.output.decode(errors="ignore") if exc.output else str(exc)
    print(json.dumps({"check": "qdrant", "status": "FAIL", "message": f"qdrant request failed: {msg[:200]}"}, sort_keys=True))
    sys.exit(1)
except Exception as exc:
    print(json.dumps({"check": "qdrant", "status": "FAIL", "message": f"qdrant error: {exc}"}, sort_keys=True))
    sys.exit(1)

collections = [c.get("name") for c in data.get("result", {}).get("collections", []) if isinstance(c, dict)]
requested = resources.get("collections") or []
missing = [c for c in requested if c not in collections]

status = "PASS"
message = "collections listed"
if missing:
    status = "WARN"
    message = "collections missing (may be provisioned later)"

print(json.dumps({"check": "qdrant", "status": status, "message": message, "collections": collections, "missing": missing}, sort_keys=True))
PY
