#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

proposal_id="${PROPOSAL_ID:-}"
if [[ -z "${proposal_id}" ]]; then
  echo "ERROR: set PROPOSAL_ID" >&2
  exit 1
fi

if [[ "${APPLY_DRYRUN:-}" != "1" && "${PROPOSAL_APPLY:-}" != "1" ]]; then
  echo "ERROR: set PROPOSAL_APPLY=1 to apply or APPLY_DRYRUN=1 for dry-run" >&2
  exit 1
fi
if [[ "${CI:-0}" == "1" && "${PROPOSAL_APPLY:-}" == "1" ]]; then
  echo "ERROR: proposal apply is not allowed in CI" >&2
  exit 2
fi

proposal_path=$(find "${FABRIC_REPO_ROOT}/proposals/inbox" -type f -name "proposal.yml" -path "*/${proposal_id}/*" 2>/dev/null | head -n1 || true)
if [[ -z "${proposal_path}" ]]; then
  proposal_path="${FABRIC_REPO_ROOT}/examples/proposals/${proposal_id}.yml"
fi
if [[ ! -f "${proposal_path}" ]]; then
  echo "ERROR: proposal not found for ${proposal_id}" >&2
  exit 1
fi

tenant_id=$(PROPOSAL_PATH="${proposal_path}" python3 - <<'PY'
import os
import yaml
from pathlib import Path
proposal = yaml.safe_load(Path(os.environ["PROPOSAL_PATH"]).read_text())
print(proposal.get("tenant_id", ""))
PY
)

if [[ -z "${tenant_id}" ]]; then
  echo "ERROR: proposal missing tenant_id" >&2
  exit 1
fi

decision_path="${FABRIC_REPO_ROOT}/evidence/proposals/${tenant_id}/${proposal_id}/decision.json"
if [[ ! -f "${decision_path}" ]]; then
  echo "ERROR: proposal not approved (decision.json missing)" >&2
  exit 1
fi

status=$(DECISION_PATH="${decision_path}" python3 - <<'PY'
import json
import os
from pathlib import Path
payload = json.loads(Path(os.environ["DECISION_PATH"]).read_text())
print(payload.get("status", ""))
PY
)

if [[ "${status}" != "approved" ]]; then
  echo "ERROR: proposal decision is not approved (status=${status})" >&2
  exit 1
fi

env_scope=$(PROPOSAL_PATH="${proposal_path}" python3 - <<'PY'
import os
import yaml
from pathlib import Path
proposal = yaml.safe_load(Path(os.environ["PROPOSAL_PATH"]).read_text())
print(proposal.get("scope", {}).get("environment", ""))
PY
)

if [[ "${env_scope}" == "prod" ]]; then
  decision_dir="$(dirname "${decision_path}")"
  decision_sha="${decision_dir}/decision.sha256"
  decision_sig="${decision_dir}/decision.sha256.asc"
  if [[ ! -f "${decision_sig}" ]]; then
    echo "ERROR: prod proposal requires signed decision (decision.sha256.asc missing)" >&2
    exit 1
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg required to verify prod decision signature" >&2
    exit 1
  fi
  if ! gpg --verify "${decision_sig}" "${decision_sha}" >/dev/null 2>&1; then
    echo "ERROR: decision signature verification failed" >&2
    exit 1
  fi
fi

PROPOSAL_ID="${proposal_id}" bash "${FABRIC_REPO_ROOT}/ops/proposals/validate.sh"

if [[ "${APPLY_DRYRUN:-}" == "1" ]]; then
  echo "DRY_RUN: would apply proposal ${proposal_id} for tenant ${tenant_id}"
else
  echo "Applying proposal ${proposal_id} for tenant ${tenant_id}"
fi

PROPOSAL_PATH="${proposal_path}" APPLY_DRYRUN="${APPLY_DRYRUN:-}" python3 - <<'PY'
import os
import yaml
from pathlib import Path

proposal_path = Path(os.environ["PROPOSAL_PATH"])
apply = os.environ.get("APPLY_DRYRUN") != "1"

proposal = yaml.safe_load(proposal_path.read_text())
changes = proposal.get("changes", []) if isinstance(proposal, dict) else []

ops = []
for change in changes:
    if not isinstance(change, dict):
        continue
    action = change.get("action")
    kind = change.get("kind")
    target = change.get("target")
    if kind != "binding" or action == "remove":
        ops.append({"action": action, "kind": kind, "target": target, "apply": False})
        continue
    if not target:
        continue
    ops.append({"action": action, "kind": kind, "target": target, "apply": True})

print("\n".join([f"{o['action']} {o['kind']}: {o['target']}" for o in ops]))
PY

if [[ "${APPLY_DRYRUN:-}" == "1" ]]; then
  exit 0
fi

while IFS= read -r target; do
  if [[ -z "${target}" ]]; then
    continue
  fi
  binding_path="${FABRIC_REPO_ROOT}/${target}"
  if [[ ! -f "${binding_path}" ]]; then
    echo "ERROR: binding target missing: ${binding_path}" >&2
    exit 1
  fi
  read -r workload_id < <(BINDING_PATH="${binding_path}" python3 - <<'PY'
import os
import yaml
from pathlib import Path
binding = yaml.safe_load(Path(os.environ["BINDING_PATH"]).read_text())
print(binding.get("metadata", {}).get("workload_id", ""))
PY
)
  if [[ -z "${workload_id}" ]]; then
    echo "ERROR: workload_id missing in ${binding_path}" >&2
    exit 1
  fi
  make -C "${FABRIC_REPO_ROOT}" bindings.apply TENANT="${tenant_id}" WORKLOAD="${workload_id}" BIND_EXECUTE="${BIND_EXECUTE:-}"

done < <(PROPOSAL_PATH="${proposal_path}" python3 - <<'PY'
import os
import yaml
from pathlib import Path
proposal = yaml.safe_load(Path(os.environ["PROPOSAL_PATH"]).read_text())
for change in proposal.get("changes", []):
    if isinstance(change, dict) and change.get("kind") == "binding" and change.get("action") in {"add", "modify"}:
        print(change.get("target", ""))
PY
)
