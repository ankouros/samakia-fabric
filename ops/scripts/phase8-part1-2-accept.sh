#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

acceptance_dir="${FABRIC_REPO_ROOT}/acceptance"
marker="${acceptance_dir}/PHASE8_PART1_2_ACCEPTED.md"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: missing required file: $path" >&2
    exit 1
  fi
}

require_exec() {
  local path="$1"
  if [[ ! -x "$path" ]]; then
    echo "ERROR: not executable: $path" >&2
    exit 1
  fi
}

run_cmd() {
  echo "[phase8.part1.2] $*"
  "$@"
}

run_cmd make -C "$FABRIC_REPO_ROOT" policy.check
run_cmd make -C "$FABRIC_REPO_ROOT" phase8.entry.check

require_file "${FABRIC_REPO_ROOT}/tools/image-toolchain/Dockerfile"
require_file "${FABRIC_REPO_ROOT}/tools/image-toolchain/versions.env"
require_file "${FABRIC_REPO_ROOT}/tools/image-toolchain/README.md"
require_exec "${FABRIC_REPO_ROOT}/ops/images/vm/toolchain-run.sh"

for key in PACKER_VERSION ANSIBLE_VERSION QEMU_UTILS_VERSION LIBGUESTFS_TOOLS_VERSION JQ_VERSION YQ_VERSION; do
  if ! grep -q "^${key}=" "${FABRIC_REPO_ROOT}/tools/image-toolchain/versions.env"; then
    echo "ERROR: versions.env missing ${key}" >&2
    exit 1
  fi
  val="$(grep -E "^${key}=" "${FABRIC_REPO_ROOT}/tools/image-toolchain/versions.env" | cut -d= -f2-)"
  if [[ -z "$val" ]]; then
    echo "ERROR: versions.env has empty value for ${key}" >&2
    exit 1
  fi
 done

if ! rg -q "image\.toolchain\.build" "${FABRIC_REPO_ROOT}/Makefile"; then
  echo "ERROR: Makefile missing image.toolchain.build target" >&2
  exit 1
fi

if ! rg -q "toolchain" "${FABRIC_REPO_ROOT}/docs/images/local-build-and-validate.md"; then
  echo "ERROR: local build runbook does not reference toolchain" >&2
  exit 1
fi

if ! rg -q "image-toolchain" "${FABRIC_REPO_ROOT}/OPERATIONS.md"; then
  echo "ERROR: OPERATIONS.md missing toolchain reference" >&2
  exit 1
fi

if [[ "${TOOLCHAIN_BUILD:-0}" == "1" ]]; then
  if command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1; then
    runtime="docker"
    if ! command -v docker >/dev/null 2>&1; then
      runtime="podman"
    fi
    image_tag="${TOOLCHAIN_IMAGE_TAG:-samakia-fabric/image-toolchain:phase8-1.2}"
    "${runtime}" build -t "${image_tag}" "${FABRIC_REPO_ROOT}/tools/image-toolchain"
    "${runtime}" run --rm "${image_tag}" packer version
    "${runtime}" run --rm "${image_tag}" ansible --version | head -n 1
    "${runtime}" run --rm "${image_tag}" guestfish --version || true
  else
    echo "WARN: docker/podman not available; skipping optional build" >&2
  fi
fi

mkdir -p "$acceptance_dir"
commit_hash="$("${FABRIC_REPO_ROOT}"/ops/scripts/git-commit-hash.sh 2>/dev/null || git -C "$FABRIC_REPO_ROOT" rev-parse HEAD)"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >"$marker" <<EOF_MARKER
# Phase 8 Part 1.2 Acceptance

Timestamp (UTC): ${stamp}
Commit: ${commit_hash}

Commands executed:
- make policy.check
- make phase8.entry.check
- phase8.part1.2 accept checks

Result: PASS

Statement:
Toolchain container is optional; no infra mutation.
EOF_MARKER

( cd "$acceptance_dir" && sha256sum "$(basename "$marker")" >"$(basename "$marker").sha256" )
