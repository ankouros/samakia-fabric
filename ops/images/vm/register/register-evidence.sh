#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

mode=""
image=""
version=""
contract=""
env_name=""
storage=""
vmid=""
node=""
template_name=""
qcow2=""
sha256_value=""
tags=""
notes=""
api_host=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      mode="$2"
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
    --contract)
      contract="$2"
      shift 2
      ;;
    --env)
      env_name="$2"
      shift 2
      ;;
    --storage)
      storage="$2"
      shift 2
      ;;
    --vmid)
      vmid="$2"
      shift 2
      ;;
    --node)
      node="$2"
      shift 2
      ;;
    --name)
      template_name="$2"
      shift 2
      ;;
    --qcow2)
      qcow2="$2"
      shift 2
      ;;
    --sha256)
      sha256_value="$2"
      shift 2
      ;;
    --tags)
      tags="$2"
      shift 2
      ;;
    --notes)
      notes="$2"
      shift 2
      ;;
    --api-host)
      api_host="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
 done

if [[ -z "$mode" || -z "$image" || -z "$version" || -z "$contract" || -z "$env_name" || -z "$storage" || -z "$vmid" || -z "$node" || -z "$template_name" ]]; then
  echo "ERROR: missing required args for register-evidence.sh" >&2
  exit 2
fi

if [[ "$mode" != "register" && "$mode" != "verify" ]]; then
  echo "ERROR: --mode must be register or verify" >&2
  exit 2
fi

if [[ -z "$sha256_value" ]]; then
  echo "ERROR: --sha256 is required" >&2
  exit 2
fi

if [[ ! -f "$contract" ]]; then
  echo "ERROR: contract not found: $contract" >&2
  exit 1
fi

if [[ -n "$qcow2" && ! -f "$qcow2" ]]; then
  echo "ERROR: qcow2 not found: $qcow2" >&2
  exit 1
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="${FABRIC_REPO_ROOT}/evidence/images/vm/${image}/${version}/${stamp}/${mode}"
mkdir -p "$out_dir"

printf '%s\n' "${sha256_value}" >"${out_dir}/qcow2.sha256"
sha256sum "$contract" >"${out_dir}/contract.sha256"

cat >"${out_dir}/report.md" <<EOF_REPORT
# VM Template ${mode^} Evidence

- image: ${image}
- version: ${version}
- env: ${env_name}
- node: ${node}
- vmid: ${vmid}
- storage: ${storage}
- template_name: ${template_name}
- qcow2: ${qcow2}
- qcow2_sha256: ${sha256_value}
- contract: ${contract}
- timestamp_utc: ${stamp}
- result: PASS
EOF_REPORT

export OUT_DIR="$out_dir"
export IMAGE="$image"
export VERSION="$version"
export ENV_NAME="$env_name"
export NODE="$node"
export VMID="$vmid"
export STORAGE="$storage"
export TEMPLATE_NAME="$template_name"
export QCOW2="$qcow2"
export SHA256_VALUE="$sha256_value"
export TAGS="$tags"
export NOTES="$notes"
export API_HOST="$api_host"
export CONTRACT="$contract"
export STAMP="$stamp"

python3 - <<'PY'
import json
import os
from pathlib import Path

out_dir = Path(os.environ["OUT_DIR"])
metadata = {
    "image": os.environ["IMAGE"],
    "version": os.environ["VERSION"],
    "env": os.environ["ENV_NAME"],
    "node": os.environ["NODE"],
    "vmid": os.environ["VMID"],
    "storage": os.environ["STORAGE"],
    "template_name": os.environ["TEMPLATE_NAME"],
    "qcow2": os.environ["QCOW2"],
    "qcow2_sha256": os.environ["SHA256_VALUE"],
    "contract": os.environ["CONTRACT"],
    "timestamp_utc": os.environ["STAMP"],
    "result": "PASS",
}
(out_dir / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")

proxmox = {
    "api_host": os.environ.get("API_HOST", ""),
    "node": os.environ["NODE"],
    "vmid": os.environ["VMID"],
    "template_name": os.environ["TEMPLATE_NAME"],
    "storage": os.environ["STORAGE"],
    "tags": os.environ.get("TAGS", ""),
    "notes": os.environ.get("NOTES", ""),
}
(out_dir / "proxmox.json").write_text(json.dumps(proxmox, indent=2) + "\n")
PY

( cd "$out_dir" && sha256sum report.md metadata.json qcow2.sha256 contract.sha256 proxmox.json > manifest.sha256 )

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
