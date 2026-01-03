#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

image=""
version=""
build_time=""
git_sha=""
packer_template=""
base_image_digest=""
apt_snapshot=""
apt_snapshot_security=""
ansible_playbook=""
image_kind=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      image="$2"
      shift 2
      ;;
    --version)
      version="$2"
      shift 2
      ;;
    --build-time)
      build_time="$2"
      shift 2
      ;;
    --git-sha)
      git_sha="$2"
      shift 2
      ;;
    --packer-template)
      packer_template="$2"
      shift 2
      ;;
    --base-image-digest)
      base_image_digest="$2"
      shift 2
      ;;
    --apt-snapshot)
      apt_snapshot="$2"
      shift 2
      ;;
    --apt-snapshot-security)
      apt_snapshot_security="$2"
      shift 2
      ;;
    --ansible-playbook)
      ansible_playbook="$2"
      shift 2
      ;;
    --image-kind)
      image_kind="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
 done

if [[ -z "$image" || -z "$version" || -z "$build_time" || -z "$git_sha" || -z "$packer_template" || -z "$base_image_digest" || -z "$apt_snapshot" ]]; then
  echo "ERROR: --image, --version, --build-time, --git-sha, --packer-template, --base-image-digest, and --apt-snapshot are required" >&2
  exit 2
fi

if [[ "$base_image_digest" == *"@"* ]]; then
  base_image_digest="${base_image_digest#*@}"
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="${FABRIC_REPO_ROOT}/evidence/images/${image}/${version}/${stamp}"
mkdir -p "$out_dir"

packer_version="unknown"
if command -v packer >/dev/null 2>&1; then
  packer_version="$(packer version 2>/dev/null | head -n 1 | awk '{print $2}' || echo unknown)"
fi

ansible_version="unknown"
ansible_enabled="false"
if [[ -n "$ansible_playbook" ]]; then
  ansible_enabled="true"
  if command -v ansible >/dev/null 2>&1; then
    ansible_version="$(ansible --version 2>/dev/null | head -n 1 | awk '{print $2}' || echo unknown)"
  fi
fi

export OUT_DIR="$out_dir"
export IMAGE="$image"
export VERSION="$version"
export IMAGE_KIND="$image_kind"
export BASE_IMAGE_DIGEST="$base_image_digest"
export APT_SNAPSHOT="$apt_snapshot"
export APT_SNAPSHOT_SECURITY="$apt_snapshot_security"
export PACKER_TEMPLATE="$packer_template"
export BUILD_TIME="$build_time"
export GIT_SHA="$git_sha"
export PACKER_VERSION="$packer_version"
export ANSIBLE_ENABLED="$ansible_enabled"
export ANSIBLE_PLAYBOOK="$ansible_playbook"
export ANSIBLE_VERSION="$ansible_version"

python3 - <<'PY'
import json
import os
from pathlib import Path

out_dir = Path(os.environ["OUT_DIR"])

def write_json(name, payload):
    (out_dir / name).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")

write_json("inputs.json", {
    "image": os.environ["IMAGE"],
    "version": os.environ["VERSION"],
    "image_kind": os.environ.get("IMAGE_KIND", ""),
    "base_image_digest": os.environ["BASE_IMAGE_DIGEST"],
    "apt_snapshot": os.environ["APT_SNAPSHOT"],
    "apt_snapshot_security": os.environ.get("APT_SNAPSHOT_SECURITY", ""),
})

write_json("packer.json", {
    "template": os.environ["PACKER_TEMPLATE"],
    "build_time": os.environ["BUILD_TIME"],
    "git_sha": os.environ["GIT_SHA"],
    "packer_version": os.environ.get("PACKER_VERSION", "unknown"),
})

write_json("ansible.json", {
    "enabled": os.environ.get("ANSIBLE_ENABLED", "false"),
    "playbook": os.environ.get("ANSIBLE_PLAYBOOK", ""),
    "ansible_version": os.environ.get("ANSIBLE_VERSION", "unknown"),
})
PY

cat >"${out_dir}/provenance.txt" <<PROV
IMAGE_NAME=${IMAGE}
IMAGE_VERSION=${VERSION}
BUILD_UTC=${BUILD_TIME}
GIT_SHA=${GIT_SHA}
PACKER_TEMPLATE=${PACKER_TEMPLATE}
BASE_IMAGE_DIGEST=${BASE_IMAGE_DIGEST}
APT_SNAPSHOT=${APT_SNAPSHOT}
PROV

( cd "$out_dir" && sha256sum inputs.json packer.json ansible.json provenance.txt > manifest.sha256 )

printf '%s\n' "$out_dir"
