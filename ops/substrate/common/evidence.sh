#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


write_manifest() {
  local dir="$1"
  (cd "${dir}" && find . -type f ! -name "manifest.sha256" -print0 | sort -z | xargs -0 sha256sum > manifest.sha256)
}

write_metadata() {
  local dest="$1"
  local tenant_id="$2"
  local kind="$3"
  local stamp="$4"
  python3 - <<PY
import json
from pathlib import Path

Path("${dest}").mkdir(parents=True, exist_ok=True)
Path("${dest}/metadata.json").write_text(
    json.dumps(
        {
            "tenant_id": "${tenant_id}",
            "timestamp_utc": "${stamp}",
            "kind": "${kind}",
            "git_commit": "$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)",
        },
        indent=2,
        sort_keys=True,
    )
    + "\n"
)
PY
}
