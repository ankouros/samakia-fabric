#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

validate_allowlist() {
  local path="$1"
  if [[ -z "${path}" ]]; then
    echo "ERROR: allowlist path required" >&2
    exit 1
  fi
  MCP_ALLOWLIST_PATH="${path}" MCP_ALLOWLIST_KIND="${MCP_ALLOWLIST_KIND:-}" python3 - <<'PY'
import os
import re
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for allowlist validation: {exc}")

path = Path(os.environ["MCP_ALLOWLIST_PATH"])
kind = os.environ.get("MCP_ALLOWLIST_KIND") or ""

if not path.exists():
    raise SystemExit(f"ERROR: allowlist file missing: {path}")

payload = yaml.safe_load(path.read_text(encoding="utf-8"))
if not isinstance(payload, dict):
    raise SystemExit("ERROR: allowlist must be a mapping")

internal_re = re.compile(r"^https?://(192\.168\.|10\.|127\.|localhost)")


def ensure_roots():
    roots = payload.get("roots", [])
    if not isinstance(roots, list) or not roots:
        raise SystemExit("ERROR: allowlist roots must be a non-empty list")
    for root in roots:
        if not isinstance(root, str) or root.startswith("/") or ".." in root:
            raise SystemExit(f"ERROR: invalid allowlist root: {root}")


def ensure_base_url(value, label):
    if not isinstance(value, str) or not internal_re.match(value):
        raise SystemExit(f"ERROR: {label} must be internal (got {value})")


if kind in {"repo", "evidence", "runbooks"}:
    ensure_roots()
elif kind == "observability":
    prom = payload.get("prometheus", {})
    loki = payload.get("loki", {})
    ensure_base_url(prom.get("base_url"), "prometheus.base_url")
    ensure_base_url(loki.get("base_url"), "loki.base_url")
    for section_name, section in (("prometheus", prom), ("loki", loki)):
        queries = section.get("queries", [])
        if not isinstance(queries, list) or not queries:
            raise SystemExit(f"ERROR: {section_name}.queries must be a non-empty list")
        for item in queries:
            if not isinstance(item, dict) or "name" not in item or "expr" not in item:
                raise SystemExit(f"ERROR: {section_name}.queries entries must include name/expr")
elif kind == "qdrant":
    ensure_base_url(payload.get("base_url"), "base_url")
else:
    raise SystemExit(f"ERROR: unknown MCP allowlist kind: {kind}")

print(f"PASS allowlist ({kind}): {path}")
PY
}
