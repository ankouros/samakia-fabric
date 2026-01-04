#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  cutover-validate.sh --file <cutover.yml> [--out <json>]

Notes:
  - Validates the cutover contract schema.
  - Ensures binding targets exist and reference the old secret_ref.
  - Validates old/new secret refs exist in the configured secrets backend.
  - Emits normalized JSON (stdout or --out).
EOT
}

file="${FILE:-}"
out=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      file="$2"
      shift 2
      ;;
    --out)
      out="$2"
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

if [[ -z "${file}" ]]; then
  usage
  exit 2
fi

schema="${FABRIC_REPO_ROOT}/contracts/rotation/cutover.schema.json"
backend="${BIND_SECRETS_BACKEND:-vault}"
backend_script="${FABRIC_REPO_ROOT}/ops/bindings/secrets/backends/${backend}.sh"
if [[ ! -f "${schema}" ]]; then
  echo "ERROR: schema not found: ${schema}" >&2
  exit 2
fi

if [[ ! -f "${file}" ]]; then
  echo "ERROR: cutover file not found: ${file}" >&2
  exit 2
fi

if [[ ! -x "${backend_script}" ]]; then
  echo "ERROR: secrets backend not found or not executable: ${backend_script}" >&2
  exit 2
fi

normalized=$(CUTOVER_FILE="${file}" CUTOVER_SCHEMA="${schema}" FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" SECRETS_BACKEND="${backend}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path
import yaml
import jsonschema

cutover_path = Path(os.environ["CUTOVER_FILE"])
schema_path = Path(os.environ["CUTOVER_SCHEMA"])
root = Path(os.environ["FABRIC_REPO_ROOT"]).resolve()
bindings_root = (root / "contracts" / "bindings" / "tenants").resolve()
secrets_backend = os.environ.get("SECRETS_BACKEND") or ""

data = None
if cutover_path.suffix in {".yml", ".yaml"}:
    data = yaml.safe_load(cutover_path.read_text())
else:
    data = json.loads(cutover_path.read_text())

schema = json.loads(schema_path.read_text())
jsonschema.validate(instance=data, schema=schema)

meta = data.get("metadata", {})
spec = data.get("spec", {})

tenant = meta.get("tenant")
env_name = meta.get("env")
workload = meta.get("workload_id")
consumer = spec.get("consumer", {})
old_ref = spec.get("old_secret_ref")
new_ref = spec.get("new_secret_ref")
verify_mode = spec.get("verify_mode")
reason = spec.get("reason")
change_window = spec.get("change_window")

if not tenant or not env_name or not workload:
    raise SystemExit("ERROR: metadata missing tenant/env/workload_id")

if not reason or not str(reason).strip():
    raise SystemExit("ERROR: spec.reason is required")

if old_ref == new_ref:
    raise SystemExit("ERROR: old_secret_ref and new_secret_ref must differ")

if env_name in {"prod", "samakia-prod"}:
    if not change_window or not change_window.get("start") or not change_window.get("end"):
        raise SystemExit("ERROR: prod cutover requires change_window.start and change_window.end")

bindings = spec.get("bindings", [])
if not isinstance(bindings, list) or not bindings:
    raise SystemExit("ERROR: spec.bindings must be a non-empty list")

bindings_abs = []
bindings_rel = []
for path_str in bindings:
    path = (root / path_str).resolve()
    if not str(path).startswith(str(bindings_root)):
        raise SystemExit(f"ERROR: binding path must live under contracts/bindings/tenants: {path_str}")
    if not path.exists():
        raise SystemExit(f"ERROR: binding file not found: {path_str}")
    binding_data = yaml.safe_load(path.read_text())
    binding_meta = binding_data.get("metadata", {}) if isinstance(binding_data, dict) else {}
    if binding_meta.get("tenant") != tenant or binding_meta.get("env") != env_name or binding_meta.get("workload_id") != workload:
        raise SystemExit(f"ERROR: binding metadata mismatch: {path_str}")
    if old_ref not in path.read_text():
        raise SystemExit(f"ERROR: old_secret_ref not found in binding: {path_str}")
    bindings_abs.append(str(path))
    bindings_rel.append(str(path.relative_to(root)))

payload = {
    "file": str(cutover_path),
    "tenant": tenant,
    "env": env_name,
    "workload_id": workload,
    "consumer": consumer,
    "old_secret_ref": old_ref,
    "new_secret_ref": new_ref,
    "bindings": bindings_rel,
    "bindings_abs": bindings_abs,
    "verify_mode": verify_mode,
    "change_window": change_window or None,
    "reason": reason,
    "secrets_backend": secrets_backend,
}

print(json.dumps(payload, indent=2, sort_keys=True))
PY
)

mapfile -t ref_lines < <(python3 - <<'PY' "${normalized}"
import json
import sys

payload = json.loads(sys.argv[1])
print(payload.get("old_secret_ref", ""))
print(payload.get("new_secret_ref", ""))
PY
)

old_ref="${ref_lines[0]:-}"
new_ref="${ref_lines[1]:-}"

if [[ -z "${old_ref}" || -z "${new_ref}" ]]; then
  echo "ERROR: missing old_secret_ref or new_secret_ref" >&2
  exit 2
fi

if ! "${backend_script}" get "${old_ref}" >/dev/null 2>&1; then
  echo "ERROR: old_secret_ref not found in backend '${backend}': ${old_ref}" >&2
  exit 2
fi

if ! "${backend_script}" get "${new_ref}" >/dev/null 2>&1; then
  echo "ERROR: new_secret_ref not found in backend '${backend}': ${new_ref}" >&2
  exit 2
fi

if [[ -n "${out}" ]]; then
  printf '%s\n' "${normalized}" > "${out}"
else
  printf '%s\n' "${normalized}"
fi
