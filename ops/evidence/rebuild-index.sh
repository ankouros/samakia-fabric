#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


evidence_root="${FABRIC_REPO_ROOT}/evidence"
out_dir="${EVIDENCE_INDEX_OUT:-${evidence_root}}"
if [[ "${out_dir}" != /* ]]; then
  out_dir="${FABRIC_REPO_ROOT}/${out_dir}"
fi

mkdir -p "${out_dir}"

FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" OUT_DIR="${out_dir}" python3 - <<'PY'
import json
import os
import subprocess
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])
out_dir = Path(os.environ["OUT_DIR"])
acceptance_dir = root / "acceptance"


def _git_commit(path: Path) -> str:
    try:
        rel = path.relative_to(root)
    except ValueError:
        rel = path
    try:
        return (
            subprocess.check_output(
                ["git", "-C", str(root), "log", "-n", "1", "--format=%H", "--", str(rel)],
                text=True,
            )
            .strip()
        )
    except Exception:
        return "unknown"


def parse_marker(path: Path) -> dict:
    timestamp = ""
    commit = ""
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if line.startswith("Timestamp (UTC):"):
            timestamp = line.split(":", 1)[1].strip()
        elif line.startswith("Commit:"):
            commit = line.split(":", 1)[1].strip()
        elif line.startswith("Repository commit:"):
            commit = line.split(":", 1)[1].strip()
    if not commit:
        commit = _git_commit(path)
    return {
        "id": path.stem,
        "path": str(path.relative_to(root)),
        "timestamp": timestamp or "unknown",
        "commit": commit or "unknown",
    }


markers = [parse_marker(path) for path in sorted(acceptance_dir.glob("*ACCEPTED.md"))]
markers = sorted(markers, key=lambda item: item.get("id", ""))


evidence_dirs = [
    {
        "name": "exposure",
        "paths": [
            "evidence/exposure-plan",
            "evidence/exposure-approve",
            "evidence/exposure-apply",
            "evidence/exposure-verify",
            "evidence/exposure-rollback",
            "evidence/exposure-canary",
        ],
    },
    {"name": "rotation", "paths": ["evidence/rotation"]},
    {"name": "drift", "paths": ["evidence/drift"]},
    {"name": "runtime-eval", "paths": ["evidence/runtime-eval"]},
    {"name": "ai-analysis", "paths": ["evidence/ai"]},
]

payload = {
    "acceptance_markers": markers,
    "evidence_directories": evidence_dirs,
}

index_json = out_dir / "index.json"
index_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

lines = [
    "# Evidence Index",
    "",
    "## Acceptance markers",
    "| ID | Timestamp (UTC) | Commit | Path |",
    "| --- | --- | --- | --- |",
]
if markers:
    for marker in markers:
        lines.append(
            f"| {marker['id']} | {marker['timestamp']} | {marker['commit']} | `{marker['path']}` |"
        )
else:
    lines.append("| none | none | none | none |")

lines.append("")
lines.append("## Evidence directories")
for entry in evidence_dirs:
    lines.append(f"- {entry['name']}: {', '.join(entry['paths'])}")

index_md = out_dir / "INDEX.md"
index_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

echo "OK: evidence index rebuilt in ${out_dir}"
