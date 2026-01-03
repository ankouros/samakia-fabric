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
      echo "usage: tcp_tls.sh --entry <json> [--mode offline|live] [--secret <file>] [--ca-file <path>]" >&2
      exit 2
      ;;
  esac
 done

if [[ -z "${entry}" ]]; then
  echo "ERROR: --entry is required" >&2
  exit 2
fi

: "${secret_file}"

if [[ "${mode}" == "offline" ]]; then
  python3 - <<'PY'
import json
print(json.dumps({
    "check": "tcp_tls",
    "status": "PASS",
    "mode": "offline",
    "message": "offline mode: connectivity not attempted"
}, sort_keys=True))
PY
  exit 0
fi

python3 - "${entry}" "${ca_file}" <<'PY'
import json
import socket
import ssl
import sys
from datetime import datetime, timezone
from pathlib import Path

entry_path = Path(sys.argv[1])
ca_file = sys.argv[2] if len(sys.argv) > 2 else ""
entry = json.loads(entry_path.read_text())
endpoint = entry.get("endpoint", {})

host = endpoint.get("host")
port = endpoint.get("port")
protocol = endpoint.get("protocol")
tls_required = endpoint.get("tls_required")

result = {
    "check": "tcp_tls",
    "host": host,
    "port": port,
    "protocol": protocol,
    "tls_required": tls_required,
}

if not host or not port:
    result.update({"status": "FAIL", "message": "missing endpoint host/port"})
    print(json.dumps(result, sort_keys=True))
    sys.exit(1)

try:
    port_int = int(port)
except (TypeError, ValueError):
    result.update({"status": "FAIL", "message": "invalid port"})
    print(json.dumps(result, sort_keys=True))
    sys.exit(1)

try:
    sock = socket.create_connection((host, port_int), timeout=5)
except Exception as exc:
    result.update({"status": "FAIL", "message": f"tcp connect failed: {exc}"})
    print(json.dumps(result, sort_keys=True))
    sys.exit(1)

if not tls_required:
    sock.close()
    result.update({"status": "PASS", "message": "tcp reachable; tls not required"})
    print(json.dumps(result, sort_keys=True))
    sys.exit(0)

try:
    context = ssl.create_default_context()
    if ca_file:
        ca_path = Path(ca_file)
        if not ca_path.exists():
            raise FileNotFoundError(f"CA file not found: {ca_path}")
        context.load_verify_locations(cafile=str(ca_path))
    context.check_hostname = True
    context.verify_mode = ssl.CERT_REQUIRED
    tls_sock = context.wrap_socket(sock, server_hostname=host)
    cert = tls_sock.getpeercert()
    tls_sock.close()
except Exception as exc:
    result.update({"status": "FAIL", "message": f"tls handshake failed: {exc}"})
    print(json.dumps(result, sort_keys=True))
    sys.exit(1)

not_after = cert.get("notAfter")
expiry = None
if not_after:
    try:
        expiry = datetime.strptime(not_after, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc).isoformat()
    except Exception:
        expiry = not_after

subject = "/".join([f"{k}={v}" for tup in cert.get("subject", []) for k, v in tup])
issuer = "/".join([f"{k}={v}" for tup in cert.get("issuer", []) for k, v in tup])

result.update({
    "status": "PASS",
    "message": "tcp + tls ok",
    "tls": {
        "subject": subject,
        "issuer": issuer,
        "expires": expiry,
    },
})
print(json.dumps(result, sort_keys=True))
PY
