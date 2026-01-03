#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  consumer-bundle-validate.sh [--root <dir>]

Validates bundle completeness and JSON integrity.
EOT
}

ROOT_DIR="${FABRIC_REPO_ROOT}/artifacts/consumer-bundles"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_DIR="${2:-}"
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

if [[ ! -d "${ROOT_DIR}" ]]; then
  echo "ERROR: bundle root not found: ${ROOT_DIR}" >&2
  exit 1
fi

mapfile -t bundle_files < <(find "${ROOT_DIR}" -type f -name "bundle.json" -print | sort)

if [[ ${#bundle_files[@]} -eq 0 ]]; then
  echo "ERROR: no bundles found under ${ROOT_DIR}" >&2
  exit 1
fi

required_files=(
  "bundle.json"
  "bundle.md"
  "ports.txt"
  "observability-labels.txt"
  "firewall-intents.md"
  "storage-contract.md"
  "disaster-testcases.md"
)

errors=0

for bundle in "${bundle_files[@]}"; do
  bundle_dir="$(dirname "${bundle}")"
  for file in "${required_files[@]}"; do
    if [[ ! -s "${bundle_dir}/${file}" ]]; then
      echo "FAIL bundle: missing or empty ${bundle_dir}/${file}" >&2
      errors=1
    fi
  done

  BUNDLE_PATH="${bundle}" python3 - <<'PY' || errors=1
import json
import os
from pathlib import Path

bundle_path = Path(os.environ["BUNDLE_PATH"])

try:
    data = json.loads(bundle_path.read_text())
except json.JSONDecodeError as exc:
    print(f"FAIL bundle: {bundle_path} invalid JSON ({exc})")
    raise SystemExit(1)

required = ["name", "type", "variant", "network", "storage", "firewall", "observability", "disaster"]
for key in required:
    if key not in data:
        print(f"FAIL bundle: {bundle_path} missing key {key}")
        raise SystemExit(1)

print(f"PASS bundle: {bundle_path}")
PY

done

if [[ ${errors} -ne 0 ]]; then
  exit 1
fi

printf "PASS: bundle validation complete (%s bundles)\n" "${#bundle_files[@]}"
