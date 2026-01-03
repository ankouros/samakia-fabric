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
      echo "usage: dragonfly.sh --entry <json> [--mode offline|live] [--secret <file>] [--ca-file <path>]" >&2
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
print(json.dumps({"check": "dragonfly", "status": "PASS", "mode": "offline", "message": "offline mode: probe skipped"}, sort_keys=True))
PY
  exit 0
fi

if [[ -z "${secret_file}" || ! -f "${secret_file}" ]]; then
  echo "ERROR: secret file required for live dragonfly probe" >&2
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
password = secret.get("password") or secret.get("token")

host = endpoint.get("host")
port = endpoint.get("port")
if not host or not port:
    print(json.dumps({"check": "dragonfly", "status": "FAIL", "message": "missing endpoint host/port"}, sort_keys=True))
    sys.exit(1)

cmd = ["redis-cli", "-h", str(host), "-p", str(port), "--no-auth-warning"]
if endpoint.get("tls_required"):
    cmd.append("--tls")
    if ca_path and ca_path.exists():
        cmd.extend(["--cacert", str(ca_path)])
if password:
    cmd.extend(["-a", str(password)])

try:
    ping = subprocess.check_output(cmd + ["PING"], stderr=subprocess.STDOUT, timeout=5).decode().strip()
    info = subprocess.check_output(cmd + ["INFO", "SERVER"], stderr=subprocess.STDOUT, timeout=5).decode()
except subprocess.CalledProcessError as exc:
    msg = exc.output.decode(errors="ignore") if exc.output else str(exc)
    print(json.dumps({"check": "dragonfly", "status": "FAIL", "message": f"redis-cli failed: {msg[:200]}"}, sort_keys=True))
    sys.exit(1)
except Exception as exc:
    print(json.dumps({"check": "dragonfly", "status": "FAIL", "message": f"redis-cli error: {exc}"}, sort_keys=True))
    sys.exit(1)

status = "PASS" if ping.upper() == "PONG" else "WARN"
print(json.dumps({"check": "dragonfly", "status": status, "message": "ping/info ok", "ping": ping}, sort_keys=True))
PY
