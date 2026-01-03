#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat <<'USAGE'
Usage: local-run.sh <command> [options]

Commands:
  build    --image <name> --version <vN>
  validate --image <name> --version <vN> --qcow2 <path>
  evidence --image <name> --version <vN> --qcow2 <path>
  full     --image <name> --version <vN>

Guards:
  IMAGE_BUILD=1 required for build
  I_UNDERSTAND_BUILDS_TAKE_TIME=1 required for full

Optional:
  EVIDENCE_SIGN=1 EVIDENCE_GPG_KEY=<id>
USAGE
}

cmd="${1:-}"
shift || true

image=""
version=""
qcow2=""

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
    --qcow2)
      qcow2="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
 done

require_image_version() {
  if [[ -z "$image" || -z "$version" ]]; then
    echo "ERROR: --image and --version are required" >&2
    exit 2
  fi
}

case "$cmd" in
  build)
    require_image_version
    if [[ "${IMAGE_BUILD:-0}" != "1" ]]; then
      echo "FAIL: set IMAGE_BUILD=1 to run builds" >&2
      exit 2
    fi
    make -C "$FABRIC_REPO_ROOT" image.vm.build IMAGE="$image" VERSION="$version"
    echo "PASS: build completed"
    ;;
  validate)
    require_image_version
    if [[ -z "$qcow2" ]]; then
      echo "ERROR: --qcow2 is required" >&2
      exit 2
    fi
    make -C "$FABRIC_REPO_ROOT" image.validate IMAGE="$image" VERSION="$version" QCOW2="$qcow2"
    echo "PASS: validation completed"
    ;;
  evidence)
    require_image_version
    if [[ -z "$qcow2" ]]; then
      echo "ERROR: --qcow2 is required" >&2
      exit 2
    fi
    make -C "$FABRIC_REPO_ROOT" image.evidence.validate IMAGE="$image" VERSION="$version" QCOW2="$qcow2"
    echo "PASS: evidence generated"
    ;;
  full)
    require_image_version
    if [[ "${IMAGE_BUILD:-0}" != "1" ]]; then
      echo "FAIL: set IMAGE_BUILD=1 to run builds" >&2
      exit 2
    fi
    if [[ "${I_UNDERSTAND_BUILDS_TAKE_TIME:-0}" != "1" ]]; then
      echo "FAIL: set I_UNDERSTAND_BUILDS_TAKE_TIME=1 to run full workflow" >&2
      exit 2
    fi
    make -C "$FABRIC_REPO_ROOT" image.vm.build IMAGE="$image" VERSION="$version"
    out_dir="$FABRIC_REPO_ROOT/artifacts/images/vm/${image}/${version}"
    if [[ ! -d "$out_dir" ]]; then
      echo "ERROR: output directory not found: $out_dir" >&2
      exit 1
    fi
    mapfile -t qcow2_files < <(ls -1 "$out_dir"/*.qcow2 2>/dev/null || true)
    if [[ "${#qcow2_files[@]}" -ne 1 ]]; then
      echo "ERROR: expected one qcow2 artifact in $out_dir" >&2
      exit 1
    fi
    qcow2_path="${qcow2_files[0]}"
    make -C "$FABRIC_REPO_ROOT" image.validate IMAGE="$image" VERSION="$version" QCOW2="$qcow2_path"
    make -C "$FABRIC_REPO_ROOT" image.evidence.validate IMAGE="$image" VERSION="$version" QCOW2="$qcow2_path"
    echo "PASS: full build + validate + evidence completed"
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    echo "ERROR: unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
 esac
