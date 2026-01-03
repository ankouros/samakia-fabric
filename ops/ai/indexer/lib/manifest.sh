#!/usr/bin/env bash
set -euo pipefail
: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  manifest.sh --dir <path> --out <path>
EOT
}

dir_path=""
out_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      dir_path="$2"
      shift 2
      ;;
    --out)
      out_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${dir_path}" || -z "${out_path}" ]]; then
  usage
  exit 2
fi

if [[ ! -d "${dir_path}" ]]; then
  echo "ERROR: directory not found: ${dir_path}" >&2
  exit 1
fi

tmp_path="$(mktemp "${TMPDIR:-/tmp}/manifest.XXXXXX")"
cleanup() {
  rm -f "${tmp_path}"
}
trap cleanup EXIT

(
  cd "${dir_path}"
  find . -type f \
    ! -name "$(basename "${out_path}")" \
    -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >"${tmp_path}"
)

mv "${tmp_path}" "${out_path}"
trap - EXIT
