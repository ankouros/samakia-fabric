#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  echo "usage: write-artifacts.sh --plan <plan.json>" >&2
}

plan_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)
      plan_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${plan_path}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${plan_path}" ]]; then
  echo "ERROR: plan not found: ${plan_path}" >&2
  exit 1
fi

PLAN_PATH="${plan_path}" APPROVAL_REF="${APPROVAL_REF:-}" PLAN_REF="${PLAN_REF:-}" \
MODE="${MODE:-execute}" APPLIED_AT="${APPLIED_AT:-}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" \
python3 - <<'PY'
import json
import os
from pathlib import Path

plan_path = Path(os.environ["PLAN_PATH"])
plan = json.loads(plan_path.read_text())

tenant = plan.get("tenant")
workload = plan.get("workload")
env_name = plan.get("env")

if not tenant or not workload or not env_name:
    raise SystemExit("ERROR: plan missing tenant/workload/env")

approval_ref = os.environ.get("APPROVAL_REF")
plan_ref = os.environ.get("PLAN_REF")
mode = os.environ.get("MODE") or "execute"
applied_at = os.environ.get("APPLIED_AT") or ""

root = Path(os.environ["FABRIC_REPO_ROOT"]) if os.environ.get("FABRIC_REPO_ROOT") else Path.cwd()
base_prefix = Path("artifacts") / "exposure" / env_name / tenant / workload

artifacts = plan.get("artifacts", [])
if not artifacts:
    raise SystemExit("ERROR: plan contains no artifacts")

created = []
for artifact in artifacts:
    rel_path = artifact.get("path")
    if not rel_path:
        raise SystemExit("ERROR: plan artifact missing path")
    rel = Path(rel_path)
    if rel.is_absolute():
        raise SystemExit(f"ERROR: artifact path must be repo-relative: {rel_path}")
    if not str(rel).startswith(str(base_prefix)):
        raise SystemExit(f"ERROR: artifact path outside exposure root: {rel_path}")

    out_dir = root / rel
    out_dir.mkdir(parents=True, exist_ok=True)

    tags = artifact.get("tags", {})
    bundle = {
        "tenant": tenant,
        "workload": workload,
        "env": env_name,
        "provider": tags.get("provider"),
        "variant": tags.get("variant"),
        "policy_version": tags.get("policy_version"),
        "applied_at": applied_at,
        "approval_ref": approval_ref,
        "plan_ref": plan_ref,
        "mode": mode,
    }
    (out_dir / "bundle.json").write_text(json.dumps(bundle, indent=2, sort_keys=True) + "\n")
    created.append(str(rel))

print("\n".join(created))
PY
