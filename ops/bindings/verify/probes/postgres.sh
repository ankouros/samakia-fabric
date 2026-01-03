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
      echo "usage: postgres.sh --entry <json> [--mode offline|live] [--secret <file>] [--ca-file <path>]" >&2
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
print(json.dumps({"check": "postgres", "status": "PASS", "mode": "offline", "message": "offline mode: probe skipped"}, sort_keys=True))
PY
  exit 0
fi

if [[ -z "${secret_file}" || ! -f "${secret_file}" ]]; then
  echo "ERROR: secret file required for live postgres probe" >&2
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
database = secret.get("database") or resources.get("database") or "postgres"

host = endpoint.get("host")
port = endpoint.get("port")
if not host or not port:
    print(json.dumps({"check": "postgres", "status": "FAIL", "message": "missing endpoint host/port"}, sort_keys=True))
    sys.exit(1)

if not user or not password:
    print(json.dumps({"check": "postgres", "status": "FAIL", "message": "missing username/password in secret"}, sort_keys=True))
    sys.exit(1)

sslmode = "verify-full" if endpoint.get("tls_required") else "disable"
psql_cmd = [
    "psql",
    f"host={host}",
    f"port={port}",
    f"dbname={database}",
    f"user={user}",
    f"sslmode={sslmode}",
]
if ca_path and ca_path.exists():
    psql_cmd.append(f"sslrootcert={ca_path}")

env = os.environ.copy()
env["PGPASSWORD"] = str(password)
env["PGOPTIONS"] = "--default_transaction_read_only=on"

queries = [
    "SHOW default_transaction_read_only;",
    "SELECT 1;",
    "SELECT current_user;",
    "SELECT datname FROM pg_database ORDER BY datname LIMIT 5;",
]

try:
    output = subprocess.check_output(psql_cmd + ["-v", "ON_ERROR_STOP=1", "-t", "-A", "-c", " ".join(queries)], env=env, stderr=subprocess.STDOUT, timeout=10)
    text = output.decode()
except subprocess.CalledProcessError as exc:
    msg = exc.output.decode(errors="ignore") if exc.output else str(exc)
    print(json.dumps({"check": "postgres", "status": "FAIL", "message": f"psql failed: {msg[:200]}"}, sort_keys=True))
    sys.exit(1)
except Exception as exc:
    print(json.dumps({"check": "postgres", "status": "FAIL", "message": f"psql error: {exc}"}, sort_keys=True))
    sys.exit(1)

read_only = "on" in text.splitlines()[0].strip() if text.splitlines() else False

status = "PASS"
message = "read-only queries succeeded"
if access_mode == "read" and not read_only:
    status = "WARN"
    message = "read-only mode not enforced by server; client enforced"

print(json.dumps({
    "check": "postgres",
    "status": status,
    "message": message,
    "access_mode": access_mode,
    "read_only": read_only,
}, sort_keys=True))
PY
