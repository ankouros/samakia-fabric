#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


qcow2=""
image=""
version=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qcow2)
      qcow2="$2"
      shift 2
      ;;
    --image)
      image="$2"
      shift 2
      ;;
    --version)
      version="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
 done

if [[ -z "$qcow2" || -z "$image" || -z "$version" ]]; then
  echo "ERROR: --qcow2, --image, and --version are required" >&2
  exit 2
fi

if [[ ! -f "$qcow2" ]]; then
  echo "ERROR: qcow2 not found: $qcow2" >&2
  exit 1
fi

"${FABRIC_REPO_ROOT}/ops/images/vm/validate/validate-image.sh" --qcow2 "$qcow2"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="${FABRIC_REPO_ROOT}/evidence/images/vm/${image}/${version}/${stamp}/validate"
mkdir -p "$out_dir"

sha256sum "$qcow2" >"${out_dir}/artifact.sha256"

cat >"${out_dir}/report.md" <<EOF_REPORT
# VM Image Validation Evidence

- image: ${image}
- version: ${version}
- artifact: ${qcow2}
- timestamp_utc: ${stamp}
- result: PASS
EOF_REPORT

export OUT_DIR="${out_dir}"
export IMAGE="${image}"
export VERSION="${version}"
export QCOW2="${qcow2}"
export STAMP="${stamp}"

python3 - <<'PY'
import json
import os
from pathlib import Path

out_dir = Path(os.environ["OUT_DIR"])
metadata = {
    "image": os.environ["IMAGE"],
    "version": os.environ["VERSION"],
    "artifact": os.environ["QCOW2"],
    "timestamp_utc": os.environ["STAMP"],
    "result": "PASS",
}
(out_dir / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
PY

( cd "$out_dir" && sha256sum report.md metadata.json artifact.sha256 > manifest.sha256 )

if [[ "${EVIDENCE_SIGN:-0}" == "1" ]]; then
  if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg is required for signing evidence" >&2
    exit 1
  fi
  if [[ -z "${EVIDENCE_GPG_KEY:-}" ]]; then
    echo "ERROR: EVIDENCE_GPG_KEY is required when EVIDENCE_SIGN=1" >&2
    exit 1
  fi
  gpg --batch --yes --local-user "${EVIDENCE_GPG_KEY}" --armor --detach-sign "${out_dir}/manifest.sha256"
fi

printf '%s\n' "$out_dir"
