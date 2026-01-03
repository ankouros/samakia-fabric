#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


cookbook="${FABRIC_REPO_ROOT}/docs/operator/cookbook.md"
inv_json="${FABRIC_REPO_ROOT}/ops/docs/operator-targets.json"

if [[ ! -f "${cookbook}" ]]; then
  echo "cookbook missing: ${cookbook}" >&2
  exit 1
fi

if [[ ! -f "${inv_json}" ]]; then
  echo "operator inventory missing: ${inv_json}" >&2
  exit 1
fi

python3 - <<'PY'
import json
import os
import re
import sys
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])
cookbook = root / "docs/operator/cookbook.md"
inv_json = root / "ops/docs/operator-targets.json"
waivers_file = root / "ops/docs/waivers.yml"

text = cookbook.read_text(encoding="utf-8")

required_subheads = [
    "#### Intent",
    "#### Preconditions",
    "#### Command",
    "#### Expected result",
    "#### Evidence outputs",
    "#### Failure modes",
    "#### Rollback / safe exit",
]

# Validate task templates
blocks = []
current = None
for line in text.splitlines():
    if line.startswith("### Task:"):
        if current:
            blocks.append(current)
        current = {"title": line.strip(), "lines": []}
    elif current is not None:
        current["lines"].append(line)
if current:
    blocks.append(current)

errors = []
for block in blocks:
    body = "\n".join(block["lines"])
    for sub in required_subheads:
        if sub not in body:
            errors.append(f"{block['title']}: missing {sub}")

# Load inventory targets
inv = json.loads(inv_json.read_text(encoding="utf-8"))

# Load waivers (simple YAML list parser)
waived = set()
if waivers_file.exists():
    for line in waivers_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("- name:"):
            waived.add(line.split(":", 1)[1].strip())

# Check target presence
missing = []
for target in inv:
    if target in waived:
        continue
    if f"make {target}" in text or re.search(rf"\b{re.escape(target)}\b", text):
        continue
    missing.append(target)

# Link checks (relative links only)
link_errors = []
link_re = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
for match in link_re.finditer(text):
    href = match.group(1).strip()
    if href.startswith("http://") or href.startswith("https://"):
        continue
    if href.startswith("#"):
        continue
    if href.startswith("mailto:"):
        continue
    link_path = (cookbook.parent / href).resolve()
    if not link_path.exists():
        link_errors.append(f"missing link target: {href}")

if errors or missing or link_errors:
    for err in errors:
        print(f"ERROR: {err}", file=sys.stderr)
    for target in missing:
        print(f"ERROR: cookbook missing target: {target}", file=sys.stderr)
    for err in link_errors:
        print(f"ERROR: {err}", file=sys.stderr)
    sys.exit(1)

print("PASS: cookbook lint")
PY
