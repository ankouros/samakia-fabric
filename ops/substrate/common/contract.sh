#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/substrate/common/env.sh"

list_enabled_contracts() {
  local tenant_dir="$1"
  local provider_filter="$2"

  TENANT_DIR="${tenant_dir}" PROVIDER_FILTER="${provider_filter}" python3 - <<'PY'
import json
import os
from pathlib import Path

tenant_dir = Path(os.environ["TENANT_DIR"])
provider_filter = os.environ.get("PROVIDER_FILTER") or None

entries = []
for enabled in sorted(tenant_dir.rglob("consumers/*/enabled.yml")):
    data = json.loads(enabled.read_text())
    consumer = data.get("consumer")
    if consumer not in {"database", "message-queue", "cache", "vector"}:
        continue
    provider = data.get("executor", {}).get("provider")
    if provider_filter and provider != provider_filter:
        continue
    entries.append(
        {
            "path": str(enabled),
            "consumer": consumer,
            "provider": provider,
            "variant": data.get("variant"),
            "endpoints": data.get("endpoints", {}),
            "secret_ref": data.get("secret_ref"),
            "resources": data.get("resources", {}),
            "dr": data.get("dr", {}),
        }
    )

print(json.dumps(entries, indent=2, sort_keys=True))
PY
}
