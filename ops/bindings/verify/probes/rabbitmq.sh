#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


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
      echo "usage: rabbitmq.sh --entry <json> [--mode offline|live] [--secret <file>] [--ca-file <path>]" >&2
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
print(json.dumps({"check": "rabbitmq", "status": "PASS", "mode": "offline", "message": "offline mode: probe skipped"}, sort_keys=True))
PY
  exit 0
fi

if [[ -z "${secret_file}" || ! -f "${secret_file}" ]]; then
  echo "ERROR: secret file required for live rabbitmq probe" >&2
  exit 2
fi

python3 - "${entry}" "${secret_file}" "${ca_file}" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

entry_path = Path(sys.argv[1])
secret_path = Path(sys.argv[2])
ca_path = Path(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] else None

entry = json.loads(entry_path.read_text())
endpoint = entry.get("endpoint", {})

secret = json.loads(secret_path.read_text())
user = secret.get("username") or secret.get("user")
password = secret.get("password")

host = endpoint.get("host")
port = endpoint.get("port")
protocol = endpoint.get("protocol") or "https"
if not host or not port:
    print(json.dumps({"check": "rabbitmq", "status": "FAIL", "message": "missing endpoint host/port"}, sort_keys=True))
    sys.exit(1)

if not user or not password:
    print(json.dumps({"check": "rabbitmq", "status": "FAIL", "message": "missing username/password in secret"}, sort_keys=True))
    sys.exit(1)

url = f"{protocol}://{host}:{port}/api/overview"
cmd = ["curl", "--silent", "--show-error", "--fail", "--connect-timeout", "5", "--max-time", "10", "-u", f"{user}:{password}", url]
if ca_path and ca_path.exists():
    cmd.extend(["--cacert", str(ca_path)])

try:
    output = subprocess.check_output(cmd, stderr=subprocess.STDOUT, timeout=15)
    data = json.loads(output.decode())
    cluster = data.get("cluster_name")
    print(json.dumps({"check": "rabbitmq", "status": "PASS", "message": "management API reachable", "cluster": cluster}, sort_keys=True))
except subprocess.CalledProcessError as exc:
    msg = exc.output.decode(errors="ignore") if exc.output else str(exc)
    if "404" in msg:
        print(json.dumps({"check": "rabbitmq", "status": "WARN", "message": "management API not enabled (404)"}, sort_keys=True))
        sys.exit(0)
    if "401" in msg or "403" in msg:
        print(json.dumps({"check": "rabbitmq", "status": "FAIL", "message": "authentication failed"}, sort_keys=True))
        sys.exit(1)
    print(json.dumps({"check": "rabbitmq", "status": "FAIL", "message": f"curl failed: {msg[:200]}"}, sort_keys=True))
    sys.exit(1)
except Exception as exc:
    print(json.dumps({"check": "rabbitmq", "status": "FAIL", "message": f"curl error: {exc}"}, sort_keys=True))
    sys.exit(1)
PY
