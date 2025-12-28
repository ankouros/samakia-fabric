#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="${REPO_ROOT}/SECURITY_THREAT_MODELING.md"

usage() {
  cat >&2 <<'EOF'
Usage:
  threat-model-index.sh [--by severity|component|stride] [--format table|csv]
                        [--severity S0|S1|S2|S3|S4] [--component "<text>"] [--stride "<text>"]

Reads SECURITY_THREAT_MODELING.md and prints a deterministic index of threats.

Hard rules:
  - Read-only (no writes).
  - No network access.
EOF
}

by="severity"
format="table"
filter_severity=""
filter_component=""
filter_stride=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --by)
      by="${2:-}"
      shift 2
      ;;
    --format)
      format="${2:-}"
      shift 2
      ;;
    --severity)
      filter_severity="${2:-}"
      shift 2
      ;;
    --component)
      filter_component="${2:-}"
      shift 2
      ;;
    --stride)
      filter_stride="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ ! -f "${DOC}" ]]; then
  echo "ERROR: threat model document not found: ${DOC}" >&2
  exit 1
fi

python3 - "${DOC}" "${by}" "${format}" "${filter_severity}" "${filter_component}" "${filter_stride}" <<'PY'
import csv
import re
import sys
from dataclasses import dataclass
from pathlib import Path

doc_path = Path(sys.argv[1])
group_by = sys.argv[2]
out_format = sys.argv[3]
filter_severity = sys.argv[4].strip()
filter_component = sys.argv[5].strip().lower()
filter_stride = sys.argv[6].strip().lower()

text = doc_path.read_text(encoding="utf-8")

@dataclass(frozen=True)
class Threat:
  threat_id: str
  title: str
  components: str
  stride: str
  severity: str

threats: list[Threat] = []

# Expected entry format:
# ### TM-... — Title
# - Components: ...
# - STRIDE: ...
# - Severity: S...

entry_re = re.compile(r"(?ms)^###\\s+(TM-[A-Z0-9-]+)\\s+—\\s+(.+?)\\n(.*?)(?=^###\\s+TM-|\\Z)")

def field(block: str, name: str) -> str:
  m = re.search(rf"(?mi)^-\\s+{re.escape(name)}:\\s*(.+?)\\s*$", block)
  return m.group(1).strip() if m else "unknown"

for m in entry_re.finditer(text):
  threat_id = m.group(1).strip()
  title = m.group(2).strip()
  block = m.group(3)
  components = field(block, "Components")
  stride = field(block, "STRIDE")
  severity = field(block, "Severity")
  threats.append(Threat(threat_id, title, components, stride, severity))

def passes_filters(t: Threat) -> bool:
  if filter_severity and t.severity != filter_severity:
    return False
  if filter_component and filter_component not in t.components.lower():
    return False
  if filter_stride and filter_stride not in t.stride.lower():
    return False
  return True

threats = [t for t in threats if passes_filters(t)]

key = {
  "severity": lambda t: (t.severity, t.threat_id),
  "component": lambda t: (t.components, t.threat_id),
  "stride": lambda t: (t.stride, t.threat_id),
}.get(group_by)

if key is None:
  print(f"ERROR: invalid --by: {group_by}", file=sys.stderr)
  sys.exit(2)

threats.sort(key=key)

if out_format == "csv":
  w = csv.writer(sys.stdout)
  w.writerow(["threat_id", "title", "components", "stride", "severity"])
  for t in threats:
    w.writerow([t.threat_id, t.title, t.components, t.stride, t.severity])
  sys.exit(0)

if out_format != "table":
  print(f"ERROR: invalid --format: {out_format}", file=sys.stderr)
  sys.exit(2)

print("THREAT_ID\tSEVERITY\tCOMPONENTS\tSTRIDE\tTITLE")
for t in threats:
  print(f"{t.threat_id}\t{t.severity}\t{t.components}\t{t.stride}\t{t.title}")
PY
