#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

input_path="${FABRIC_REPO_ROOT}/hardening/checklist.json"
output_path="${FABRIC_REPO_ROOT}/hardening/checklist.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      input_path="$2"
      shift 2
      ;;
    --output)
      output_path="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

INPUT_PATH="${input_path}" OUTPUT_PATH="${output_path}" python3 - <<'PY'
import json
import os
import re
import subprocess
from datetime import datetime, timezone

input_path = os.environ.get("INPUT_PATH")
output_path = os.environ.get("OUTPUT_PATH")
repo_root = os.environ.get("FABRIC_REPO_ROOT")

if not input_path or not output_path or not repo_root:
    raise SystemExit("INPUT_PATH, OUTPUT_PATH, and FABRIC_REPO_ROOT must be set")

with open(input_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

try:
    import jsonschema
except Exception as exc:  # pragma: no cover - dependency required
    raise SystemExit(f"jsonschema is required: {exc}")

schema_path = os.path.join(repo_root, "hardening", "checklist.schema.json")
with open(schema_path, "r", encoding="utf-8") as fh:
    schema = json.load(fh)

jsonschema.validate(instance=data, schema=schema)

placeholder_re = re.compile(r"(TODO|TBD|PLACEHOLDER|<placeholder>|FIXME)", re.IGNORECASE)

def assert_no_placeholder(value: str, field: str) -> None:
    if placeholder_re.search(value or ""):
        raise SystemExit(f"placeholder text found in {field}")

category_ids = set()
check_ids = set()

for category in data["categories"]:
    cat_id = category["id"]
    if cat_id in category_ids:
        raise SystemExit(f"duplicate category id: {cat_id}")
    category_ids.add(cat_id)
    assert_no_placeholder(category.get("title", ""), f"category.title:{cat_id}")
    assert_no_placeholder(category.get("description", ""), f"category.description:{cat_id}")
    for check in category["checks"]:
        check_id = check["id"]
        if check_id in check_ids:
            raise SystemExit(f"duplicate check id: {check_id}")
        check_ids.add(check_id)
        for field in ("description", "rationale", "expected"):
            assert_no_placeholder(check.get(field, ""), f"check.{field}:{check_id}")
        if "notes" in check and check["notes"]:
            assert_no_placeholder(check.get("notes", ""), f"check.notes:{check_id}")

        cmd = check["verification"]["ref"]
        result = subprocess.run(
            cmd,
            shell=True,
            cwd=repo_root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            check["status"] = "PASS"
            check["notes"] = ""
        else:
            if check["severity"] == "hard":
                check["status"] = "FAIL"
            else:
                check["status"] = "WARN"
            check["notes"] = f"verification failed (exit {result.returncode})"

if any(check["status"] == "WARN" and check["severity"] == "hard" for cat in data["categories"] for check in cat["checks"]):
    raise SystemExit("hard check cannot be WARN")

stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
data["generated_at"] = stamp

with open(output_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")

print(f"Checklist validated and updated: {output_path}")
PY
