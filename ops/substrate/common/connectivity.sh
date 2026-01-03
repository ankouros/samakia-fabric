#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


connectivity_check() {
  local input="$1"
  local output="$2"
  local stamp="$3"

  INPUT="${input}" OUTPUT="${output}" STAMP="${stamp}" python3 - <<'PY'
import json
import os
import socket
import ssl

input_path = os.environ["INPUT"]
output_path = os.environ["OUTPUT"]
stamp = os.environ["STAMP"]

try:
    endpoints = json.loads(open(input_path, "r", encoding="utf-8").read())
except json.JSONDecodeError as exc:
    raise SystemExit(f"invalid endpoints list: {exc}")

results = {}
ci_mode = os.environ.get("CI") == "1"

for endpoint in endpoints:
    key = endpoint.get("key")
    host = endpoint.get("host")
    port = endpoint.get("port")
    protocol = endpoint.get("protocol")
    result = {
        "status": "unknown",
        "detail": "not_checked",
        "checked_at": stamp,
    }
    if not host or not port:
        result["detail"] = "missing_endpoint"
        results[key] = result
        continue

    if ci_mode:
        result["detail"] = "ci_mode"
        results[key] = result
        continue

    try:
        if protocol == "https":
            ctx = ssl.create_default_context()
            with socket.create_connection((host, port), timeout=2) as sock:
                with ctx.wrap_socket(sock, server_hostname=host) as ssock:
                    ssock.sendall(b"GET /-/ready HTTP/1.1\r\nHost: %b\r\nConnection: close\r\n\r\n" % host.encode())
                    ssock.recv(1024)
            result["status"] = "reachable"
            result["detail"] = "https_ready"
        else:
            with socket.create_connection((host, port), timeout=2):
                pass
            result["status"] = "reachable"
            result["detail"] = "tcp_connect"
    except Exception as exc:
        result["detail"] = f"unknown: {exc.__class__.__name__}"
    results[key] = result

with open(output_path, "w", encoding="utf-8") as handle:
    handle.write(json.dumps(results, indent=2, sort_keys=True) + "\n")
PY
}
