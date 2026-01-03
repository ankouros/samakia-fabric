#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


if [[ -z "${VERIFY_PATH:-}" || -z "${OUT_PATH:-}" ]]; then
  echo "ERROR: VERIFY_PATH and OUT_PATH are required" >&2
  exit 2
fi

python3 - "${VERIFY_PATH}" "${OUT_PATH}" <<'PY'
import json
import re
import sys
from pathlib import Path

verify_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])

verify = json.loads(verify_path.read_text())

bindings = verify.get("bindings_verify", {})
observe = verify.get("substrate_observe", {})

infra = {
    "status": "PASS",
    "reasons": [],
}

if observe.get("available") and observe.get("status") == "FAIL":
    infra["status"] = "FAIL"
    infra["reasons"].append("substrate_observe:FAIL")

checks = bindings.get("checks", [])
status = bindings.get("status")

message_re = re.compile(r"tls|handshake|unreachable|connection refused|timeout", re.IGNORECASE)

if status == "FAIL":
    infra["status"] = "FAIL"
    infra["reasons"].append("bindings_verify:FAIL")

for check in checks:
    if not isinstance(check, dict):
        continue
    if check.get("status") != "FAIL":
        continue
    name = check.get("name", "")
    msg = check.get("message", "")
    if name in {"tcp_tls", "provider"} or message_re.search(str(msg)):
        infra["status"] = "FAIL"
        infra["reasons"].append(f"check:{name}")

out_path.write_text(json.dumps(infra, indent=2, sort_keys=True) + "\n")
PY
