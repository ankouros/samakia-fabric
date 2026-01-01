#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

input_path="${FABRIC_REPO_ROOT}/hardening/checklist.json"
entry_output="${FABRIC_REPO_ROOT}/acceptance/PHASE11_HARDENING_ENTRY_CHECKLIST.md"
doc_output="${FABRIC_REPO_ROOT}/docs/operator/hardening.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      input_path="$2"
      shift 2
      ;;
    --entry-output)
      entry_output="$2"
      shift 2
      ;;
    --doc-output)
      doc_output="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

INPUT_PATH="${input_path}" ENTRY_OUTPUT="${entry_output}" DOC_OUTPUT="${doc_output}" python3 - <<'PY'
import json
import os
from pathlib import Path

input_path = os.environ.get("INPUT_PATH")
entry_output = os.environ.get("ENTRY_OUTPUT")
doc_output = os.environ.get("DOC_OUTPUT")

if not input_path or not entry_output or not doc_output:
    raise SystemExit("INPUT_PATH, ENTRY_OUTPUT, and DOC_OUTPUT must be set")

with open(input_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

header = (
    "# Phase 11 Pre-Exposure Hardening Checklist\n\n"
    "WARNING: This document is auto-generated. Source of truth: hardening/checklist.json\n\n"
    f"Generated (UTC): {data.get('generated_at','')}\n"
    f"Phase: {data.get('phase','')}\n"
    f"Scope: {data.get('scope','')}\n\n"
)

def render_checks():
    lines = []
    for category in data.get("categories", []):
        lines.append(f"## {category['title']}")
        lines.append("")
        lines.append(category.get("description", ""))
        lines.append("")
        for check in category.get("checks", []):
            lines.append(f"- **{check['id']}** ({check['severity'].upper()}): {check['description']}")
            lines.append(f"  - Rationale: {check['rationale']}")
            lines.append(f"  - Verification: `{check['verification']['ref']}`")
            lines.append(f"  - Expected: {check['expected']}")
            lines.append(f"  - Status: {check['status']}")
            if check.get("notes"):
                lines.append(f"  - Notes: {check['notes']}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"

content = header + render_checks()

Path(entry_output).write_text(content, encoding="utf-8")
Path(doc_output).write_text(content, encoding="utf-8")
print(f"Rendered checklist to {entry_output} and {doc_output}")
PY
