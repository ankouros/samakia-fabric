#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

usage() {
  cat <<'USAGE'
Usage: toolchain-run.sh <command> [options]

Commands:
  build    --image <name> --version <vN>
  validate --image <name> --version <vN> --qcow2 <path>
  evidence --image <name> --version <vN> --qcow2 <path>
  full     --image <name> --version <vN>

Environment:
  TOOLCHAIN_IMAGE_TAG (optional)
  TOOLCHAIN_PRIVILEGED=1 (optional)
  TOOLCHAIN_DEVICE_KVM=1 (optional)

Guards:
  IMAGE_BUILD=1
  I_UNDERSTAND_BUILDS_TAKE_TIME=1 (for full)
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

runtime=""
if command -v docker >/dev/null 2>&1; then
  runtime="docker"
elif command -v podman >/dev/null 2>&1; then
  runtime="podman"
else
  echo "ERROR: docker or podman is required to use the toolchain" >&2
  exit 1
fi

image_tag="${TOOLCHAIN_IMAGE_TAG:-samakia-fabric/image-toolchain:phase8-1.2}"

cmd="$1"
shift

mounts=("-v" "${FABRIC_REPO_ROOT}:/workspace")

if [[ -n "${QCOW2_FIXTURE_PATH:-}" ]]; then
  qcow2_dir="$(dirname "${QCOW2_FIXTURE_PATH}")"
  if [[ "$qcow2_dir" != "${FABRIC_REPO_ROOT}"* ]]; then
    mounts+=("-v" "${qcow2_dir}:${qcow2_dir}")
  fi
fi

user_args=("--user" "$(id -u):$(id -g)")

if [[ "${TOOLCHAIN_PRIVILEGED:-0}" == "1" ]]; then
  user_args+=("--privileged")
fi

if [[ "${TOOLCHAIN_DEVICE_KVM:-0}" == "1" && -e /dev/kvm ]]; then
  user_args+=("--device" "/dev/kvm")
fi

env_args=("-e" "FABRIC_REPO_ROOT=/workspace")
for var in IMAGE_BUILD I_UNDERSTAND_BUILDS_TAKE_TIME QCOW2_FIXTURE_PATH EVIDENCE_SIGN EVIDENCE_GPG_KEY; do
  if [[ -n "${!var:-}" ]]; then
    env_args+=("-e" "${var}=${!var}")
  fi
done

if [[ -n "${GNUPGHOME:-}" && -d "${GNUPGHOME}" ]]; then
  mounts+=("-v" "${GNUPGHOME}:/home/toolchain/.gnupg")
  env_args+=("-e" "GNUPGHOME=/home/toolchain/.gnupg")
fi

printf '%s\n' "Toolchain image: ${image_tag}"

${runtime} run --rm \
  "${user_args[@]}" \
  "${env_args[@]}" \
  "${mounts[@]}" \
  --workdir /workspace \
  "${image_tag}" \
  /bin/bash -lc "packer version && ansible --version | head -n 1 && qemu-img --version && (guestfish --version || true) && /workspace/ops/images/vm/local-run.sh ${cmd} $*"
