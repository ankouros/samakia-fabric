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
      echo "usage: mariadb.sh --entry <json> [--mode offline|live] [--secret <file>] [--ca-file <path>]" >&2
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
print(json.dumps({"check": "mariadb", "status": "PASS", "mode": "offline", "message": "offline mode: probe skipped"}, sort_keys=True))
PY
  exit 0
fi

if [[ -z "${secret_file}" || ! -f "${secret_file}" ]]; then
  echo "ERROR: secret file required for live mariadb probe" >&2
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
resources = entry.get("resources", {})
access_mode = entry.get("consumer", {}).get("access_mode")

secret = json.loads(secret_path.read_text())
user = secret.get("username") or secret.get("user")
password = secret.get("password")
database = secret.get("database") or resources.get("database")

host = endpoint.get("host")
port = endpoint.get("port")
if not host or not port:
    print(json.dumps({"check": "mariadb", "status": "FAIL", "message": "missing endpoint host/port"}, sort_keys=True))
    sys.exit(1)

if not user or not password:
    print(json.dumps({"check": "mariadb", "status": "FAIL", "message": "missing username/password in secret"}, sort_keys=True))
    sys.exit(1)

ssl_mode = "VERIFY_IDENTITY" if endpoint.get("tls_required") else "DISABLED"
cmd = [
    "mysql",
    "--protocol=TCP",
    f"--host={host}",
    f"--port={port}",
    f"--user={user}",
    f"--password={password}",
    f"--ssl-mode={ssl_mode}",
    "--batch",
    "--skip-column-names",
]
if database:
    cmd.append(database)
if ca_path and ca_path.exists():
    cmd.append(f"--ssl-ca={ca_path}")

queries = " ".join([
    "SET SESSION TRANSACTION READ ONLY;",
    "SELECT @@tx_read_only;",
    "SELECT 1;",
    "SELECT USER();",
    "SHOW DATABASES;",
])

try:
    output = subprocess.check_output(cmd + ["-e", queries], stderr=subprocess.STDOUT, timeout=10)
    text = output.decode()
except subprocess.CalledProcessError as exc:
    msg = exc.output.decode(errors="ignore") if exc.output else str(exc)
    print(json.dumps({"check": "mariadb", "status": "FAIL", "message": f"mysql failed: {msg[:200]}"}, sort_keys=True))
    sys.exit(1)
except Exception as exc:
    print(json.dumps({"check": "mariadb", "status": "FAIL", "message": f"mysql error: {exc}"}, sort_keys=True))
    sys.exit(1)

read_only = "1" in text.splitlines()[0].strip() if text.splitlines() else False
status = "PASS"
message = "read-only queries succeeded"
if access_mode == "read" and not read_only:
    status = "WARN"
    message = "read-only mode not enforced by server; client enforced"

print(json.dumps({
    "check": "mariadb",
    "status": status,
    "message": message,
    "access_mode": access_mode,
    "read_only": read_only,
}, sort_keys=True))
PY
