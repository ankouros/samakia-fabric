#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOF'
Usage:
  image-next-version.sh [--dir <dir>]

Computes the next monotonic golden image version number by scanning local
artifacts:
  ubuntu-24.04-lxc-rootfs-v<N>.tar.gz

Output:
  Prints the next numeric version (N) to stdout.

Notes:
  - If no matching artifacts exist, prints 1.
  - Non-matching files are ignored.
EOF
}

dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      dir="${2:-}"
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

if [[ -z "${dir}" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/../.." && pwd)"
  dir="${repo_root}/fabric-core/packer/lxc/ubuntu-24.04"
fi

if [[ ! -d "${dir}" ]]; then
  echo "ERROR: directory not found: ${dir}" >&2
  exit 1
fi

max=0
shopt -s nullglob
for f in "${dir}"/ubuntu-24.04-lxc-rootfs-v*.tar.gz; do
  base="$(basename "${f}")"
  if [[ "${base}" =~ -v([0-9]+)\.tar\.gz$ ]]; then
    n="${BASH_REMATCH[1]}"
    if (( n > max )); then
      max="${n}"
    fi
  fi
done

echo "$((max + 1))"
