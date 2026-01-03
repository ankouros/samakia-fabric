#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

evidence_root="${FABRIC_REPO_ROOT}/evidence/ai"
out_dir="${AI_EVIDENCE_INDEX_OUT:-${evidence_root}}"
if [[ "${out_dir}" != /* ]]; then
  out_dir="${FABRIC_REPO_ROOT}/${out_dir}"
fi

mkdir -p "${out_dir}"

FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" OUT_DIR="${out_dir}" python3 - <<'PY'
import json
import os
from pathlib import Path

try:
    import yaml
except Exception:
    yaml = None

root = Path(os.environ["FABRIC_REPO_ROOT"])
evidence_root = root / "evidence" / "ai"
out_dir = Path(os.environ["OUT_DIR"])

mode = os.environ.get("AI_EVIDENCE_INDEX_MODE")
if not mode:
    runner_mode = os.environ.get("RUNNER_MODE", "ci")
    mode = "local" if runner_mode == "operator" else "ci"

def load_json(path: Path):
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))

def load_yaml(path: Path):
    if not path.exists() or yaml is None:
        return {}
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}

entries = []
operator = os.environ.get("AI_OPERATOR") or "unknown"

def add_entry(entry):
    entries.append(entry)

if mode == "local":
    analysis_root = evidence_root / "analysis"
    if analysis_root.is_dir():
        for analysis_id_dir in sorted(p for p in analysis_root.iterdir() if p.is_dir()):
            for run_dir in sorted(p for p in analysis_id_dir.iterdir() if p.is_dir()):
                payload = load_yaml(run_dir / "analysis.yml.redacted")
                tenant = "unknown"
                tenant_meta = payload.get("tenant") if isinstance(payload, dict) else None
                if isinstance(tenant_meta, dict):
                    tenant = tenant_meta.get("id") or tenant
                analysis_type = payload.get("analysis_type") if isinstance(payload, dict) else None
                model_payload = load_json(run_dir / "model.json")
                model = model_payload.get("model") if isinstance(model_payload, dict) else None
                scope = f"tenant:{tenant}"
                if analysis_type:
                    scope = f"{scope} analysis:{analysis_type}"
                add_entry(
                    {
                        "timestamp": run_dir.name,
                        "type": "analysis",
                        "analysis_id": analysis_id_dir.name,
                        "analysis_type": analysis_type or "unknown",
                        "model": model or "",
                        "scope": scope,
                        "evidence_path": str(run_dir.relative_to(root)),
                    }
                )

    index_root = evidence_root / "indexing"
    if index_root.is_dir():
        for tenant_dir in sorted(p for p in index_root.iterdir() if p.is_dir()):
            for run_dir in sorted(p for p in tenant_dir.iterdir() if p.is_dir()):
                indexing = load_yaml(run_dir / "indexing.yml")
                embedding = indexing.get("embedding") if isinstance(indexing, dict) else {}
                embedding_model = embedding.get("model") if isinstance(embedding, dict) else None
                sources_payload = load_json(run_dir / "sources.json")
                sources = sources_payload.get("sources") if isinstance(sources_payload, dict) else []
                source_types = sorted({s.get("source_type") for s in sources if isinstance(s, dict) and s.get("source_type")})
                scope = f"tenant:{tenant_dir.name}"
                if source_types:
                    scope = f"{scope} sources:{','.join(source_types)}"
                add_entry(
                    {
                        "timestamp": run_dir.name,
                        "type": "indexing",
                        "tenant": tenant_dir.name,
                        "model": embedding_model or "",
                        "scope": scope,
                        "evidence_path": str(run_dir.relative_to(root)),
                    }
                )

    audit_root = evidence_root / "mcp-audit"
    if audit_root.is_dir():
        for run_dir in sorted(p for p in audit_root.iterdir() if p.is_dir()):
            stamp = run_dir.name.split("-", 1)[0]
            add_entry(
                {
                    "timestamp": stamp,
                    "type": "mcp-audit",
                    "scope": "read-only",
                    "model": "",
                    "evidence_path": str(run_dir.relative_to(root)),
                }
            )

    plan_root = evidence_root / "plan-review"
    if plan_root.is_dir():
        for env_dir in sorted(p for p in plan_root.iterdir() if p.is_dir()):
            for run_dir in sorted(p for p in env_dir.iterdir() if p.is_dir()):
                add_entry(
                    {
                        "timestamp": run_dir.name,
                        "type": "plan-review",
                        "scope": f"env:{env_dir.name}",
                        "model": "",
                        "evidence_path": str(run_dir.relative_to(root)),
                    }
                )

entries = sorted(entries, key=lambda e: (e.get("timestamp", ""), e.get("type", ""), e.get("evidence_path", "")))
counts = {}
for entry in entries:
    counts[entry.get("type", "unknown")] = counts.get(entry.get("type", "unknown"), 0) + 1

timestamps = [entry.get("timestamp") for entry in entries if entry.get("timestamp")]
generated_utc = max(timestamps) if timestamps else "none"

index_payload = {
    "generated_utc": generated_utc,
    "operator": operator,
    "mode": mode,
    "counts": counts,
    "entries": entries,
}

index_json = out_dir / "index.json"
index_json.write_text(json.dumps(index_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

lines = [
    "# AI Evidence Index",
    "",
    f"Generated (UTC): {generated_utc}",
    f"Operator: {operator}",
    f"Mode: {mode}",
    "",
    "## Counts",
]
for key in sorted(counts):
    lines.append(f"- {key}: {counts[key]}")

lines.append("")
lines.append("## Entries")
lines.append("| Timestamp | Type | Scope | Model | Evidence Path |")
lines.append("| --- | --- | --- | --- | --- |")
if entries:
    for entry in entries:
        lines.append(
            f"| {entry.get('timestamp')} | {entry.get('type')} | {entry.get('scope')} | {entry.get('model')} | `{entry.get('evidence_path')}` |"
        )
else:
    lines.append("| none | none | none | none | none |")

index_md = out_dir / "index.md"
index_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

echo "OK: AI evidence index rebuilt in ${out_dir}"
