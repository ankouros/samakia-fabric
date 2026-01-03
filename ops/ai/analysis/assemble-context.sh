#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

analysis_root="${FABRIC_REPO_ROOT}/ops/ai/analysis"

usage() {
  cat >&2 <<'EOT'
Usage: assemble-context.sh --analysis <analysis.yml> --out <inputs.json> --context <context.md>
EOT
}

analysis_file=""
out_json=""
context_md=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --analysis)
      analysis_file="$2"
      shift 2
      ;;
    --out)
      out_json="$2"
      shift 2
      ;;
    --context)
      context_md="$2"
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

if [[ -z "${analysis_file}" || -z "${out_json}" || -z "${context_md}" ]]; then
  usage
  exit 2
fi

if [[ ! -f "${analysis_file}" ]]; then
  echo "ERROR: analysis file not found: ${analysis_file}" >&2
  exit 1
fi

max_items="${AI_ANALYZE_MAX_EVIDENCE_ITEMS:-10}"
max_item_chars="${AI_ANALYZE_MAX_ITEM_CHARS:-2000}"
max_total_chars="${AI_ANALYZE_MAX_TOTAL_CHARS:-8000}"

analysis_meta="$(mktemp)"
ANALYSIS_FILE="${analysis_file}" python3 - <<'PY' >"${analysis_meta}"
import json
import os

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for analysis parsing: {exc}")

analysis_file = os.environ["ANALYSIS_FILE"]
with open(analysis_file, "r", encoding="utf-8") as handle:
    analysis = yaml.safe_load(handle)

inputs = analysis.get("inputs", {})
time_window = inputs.get("time_window", {})

meta = {
    "analysis_id": analysis.get("analysis_id"),
    "analysis_type": analysis.get("analysis_type"),
    "requester_role": analysis.get("requester_role"),
    "tenant_id": analysis.get("tenant", {}).get("id"),
    "time_window_start": time_window.get("start_utc"),
    "time_window_end": time_window.get("end_utc"),
    "evidence_refs": inputs.get("evidence_refs", []),
}

print(json.dumps(meta, indent=2, sort_keys=True))
PY

requester_role="$(python3 - "${analysis_meta}" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(payload.get("requester_role", ""))
PY
)"

tenant_id="$(python3 - "${analysis_meta}" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
print(payload.get("tenant_id", ""))
PY
)"

mapfile -t evidence_refs < <(python3 - "${analysis_meta}" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
for ref in payload.get("evidence_refs", []):
    print(ref)
PY
)

if (( ${#evidence_refs[@]} == 0 )); then
  echo "ERROR: analysis has no evidence refs" >&2
  exit 1
fi

if (( ${#evidence_refs[@]} > max_items )); then
  echo "ERROR: evidence refs exceed max (${max_items})" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
entries_file="${tmp_dir}/entries.tsv"

for ref in "${evidence_refs[@]}"; do
  raw_path="${tmp_dir}/$(basename "${ref}").raw"
  redacted_path="${tmp_dir}/$(basename "${ref}").redacted"

  MCP_IDENTITY="${MCP_IDENTITY:-operator}" MCP_TENANT="${MCP_TENANT:-platform}" \
    bash "${analysis_root}/evidence.sh" --ref "${ref}" --out "${raw_path}"

  REQUESTER_ROLE="${requester_role}" TENANT_ID="${tenant_id}" \
    bash "${analysis_root}/redact.sh" --in "${raw_path}" --out "${redacted_path}"

  printf '%s\t%s\n' "${ref}" "${redacted_path}" >>"${entries_file}"
done

MAX_ITEM_CHARS="${max_item_chars}" MAX_TOTAL_CHARS="${max_total_chars}" \
ANALYSIS_META="${analysis_meta}" ENTRIES_FILE="${entries_file}" \
OUT_JSON="${out_json}" CONTEXT_MD="${context_md}" python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

meta = json.loads(Path(os.environ["ANALYSIS_META"]).read_text(encoding="utf-8"))
entries_file = Path(os.environ["ENTRIES_FILE"])
out_json = Path(os.environ["OUT_JSON"])
context_md = Path(os.environ["CONTEXT_MD"])

max_item_chars = int(os.environ.get("MAX_ITEM_CHARS", "2000"))
max_total_chars = int(os.environ.get("MAX_TOTAL_CHARS", "8000"))

items = []
context_lines = ["# Analysis Context", "", f"Time window: {meta.get('time_window_start')} -> {meta.get('time_window_end')}", "", "## Evidence"]

total_chars = 0
truncated = False

for line in entries_file.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    ref, path = line.split("\t", 1)
    content = Path(path).read_text(encoding="utf-8", errors="ignore")
    digest = hashlib.sha256(content.encode("utf-8")).hexdigest()

    excerpt = content[:max_item_chars]
    remaining = max_total_chars - total_chars
    if remaining <= 0:
        truncated = True
        break
    if len(excerpt) > remaining:
        excerpt = excerpt[:remaining]
        truncated = True
    total_chars += len(excerpt)

    items.append({
        "ref": ref,
        "sha256": digest,
        "excerpt_chars": len(excerpt),
        "excerpt": excerpt,
    })

    context_lines.append(f"### {ref}")
    context_lines.append(excerpt)
    context_lines.append("")

tenant_value = meta.get("tenant_id")
if meta.get("requester_role") != "operator":
    tenant_value = "redacted"

payload = {
    "analysis_id": meta.get("analysis_id"),
    "analysis_type": meta.get("analysis_type"),
    "requester_role": meta.get("requester_role"),
    "tenant_id": tenant_value,
    "time_window": {
        "start_utc": meta.get("time_window_start"),
        "end_utc": meta.get("time_window_end"),
    },
    "evidence": items,
    "limits": {
        "max_item_chars": max_item_chars,
        "max_total_chars": max_total_chars,
        "max_items": len(items),
    },
    "truncated": truncated,
}

out_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
context_md.write_text("\n".join(context_lines).rstrip() + "\n", encoding="utf-8")
PY
