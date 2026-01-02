#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANT="${TENANT:-}"
if [[ -z "${TENANT}" ]]; then
  echo "ERROR: TENANT is required" >&2
  exit 2
fi

FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - "${TENANT}" <<'PY'
import json
import os
import sys
from pathlib import Path
import yaml

root = Path(os.environ["FABRIC_REPO_ROOT"])


tenant = sys.argv[1]
bindings_root = root / "contracts" / "bindings" / "tenants" / tenant
render_root = root / "artifacts" / "bindings" / tenant

issues = []
status = "PASS"


def load_yaml(path: Path):
    return yaml.safe_load(path.read_text())


def load_json(path: Path):
    return json.loads(path.read_text())


bindings = sorted(bindings_root.glob("*.binding.yml")) if bindings_root.exists() else []
manifests = sorted(render_root.glob("*/connection.json")) if render_root.exists() else []

binding_map = {}
for binding in bindings:
    data = load_yaml(binding)
    meta = data.get("metadata", {})
    spec = data.get("spec", {})
    workload_id = meta.get("workload_id")
    if not workload_id:
        issues.append({"type": "binding_invalid", "path": str(binding), "detail": "missing workload_id"})
        continue
    consumers = []
    for consumer in spec.get("consumers", []) or []:
        consumers.append({
            "type": consumer.get("type"),
            "provider": consumer.get("provider"),
            "variant": consumer.get("variant"),
        })
    binding_map[workload_id] = {"path": str(binding), "consumers": consumers}

manifest_map = {}
for manifest in manifests:
    data = load_json(manifest)
    workload_id = data.get("workload_id")
    if not workload_id:
        issues.append({"type": "render_invalid", "path": str(manifest), "detail": "missing workload_id"})
        continue
    consumers = []
    for consumer in data.get("consumers", []) or []:
        consumers.append({
            "type": consumer.get("type"),
            "provider": consumer.get("provider"),
            "variant": consumer.get("variant"),
        })
    manifest_map[workload_id] = {"path": str(manifest), "consumers": consumers}

binding_ids = set(binding_map.keys())
manifest_ids = set(manifest_map.keys())

missing = sorted(binding_ids - manifest_ids)
extra = sorted(manifest_ids - binding_ids)

for workload in missing:
    issues.append({"type": "missing_render", "workload_id": workload, "path": binding_map[workload]["path"]})

for workload in extra:
    issues.append({"type": "orphan_render", "workload_id": workload, "path": manifest_map[workload]["path"]})

for workload in sorted(binding_ids & manifest_ids):
    declared = binding_map[workload]["consumers"]
    rendered = manifest_map[workload]["consumers"]
    declared_set = {(c.get("type"), c.get("provider"), c.get("variant")) for c in declared}
    rendered_set = {(c.get("type"), c.get("provider"), c.get("variant")) for c in rendered}
    if declared_set != rendered_set:
        issues.append({
            "type": "consumer_mismatch",
            "workload_id": workload,
            "declared": sorted(list(declared_set)),
            "rendered": sorted(list(rendered_set)),
        })

if not bindings and not manifests:
    status = "WARN"
    issues.append({"type": "no_bindings", "detail": "no bindings or renders found"})
else:
    if any(issue["type"] in {"missing_render", "consumer_mismatch"} for issue in issues):
        status = "FAIL"
    elif any(issue["type"] == "orphan_render" for issue in issues):
        status = "WARN"

result = {
    "tenant": tenant,
    "status": status,
    "binding_count": len(bindings),
    "render_count": len(manifests),
    "issues": issues,
}
print(json.dumps(result, sort_keys=True, indent=2))
PY
