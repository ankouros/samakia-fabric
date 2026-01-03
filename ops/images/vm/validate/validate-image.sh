#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


qcow2=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qcow2)
      qcow2="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
 done

if [[ -z "$qcow2" ]]; then
  echo "ERROR: --qcow2 is required" >&2
  exit 2
fi

record_blocker() {
  local id="$1"
  local reason="$2"
  local file="${FABRIC_REPO_ROOT}/REQUIRED-FIXES.md"
  if ! rg -n "${id}" "$file" >/dev/null 2>&1; then
    {
      echo ""
      echo "## ${id}"
      echo "- Description: VM image validation tool missing"
      echo "- Impact: Phase 8 Part 1 acceptance blocked"
      echo "- Root cause: ${reason}"
      echo "- Required remediation: install missing tooling on runner host"
      echo "- Resolution status: OPEN"
      echo "- Verification: re-run make image.validate"
    } >>"$file"
  fi
}

if ! command -v qemu-img >/dev/null 2>&1; then
  record_blocker "PHASE8-VM-VALIDATE-QEMUIMG" "qemu-img not found in PATH"
  echo "ERROR: qemu-img is required for qcow2 validation" >&2
  exit 1
fi

if ! command -v guestfish >/dev/null 2>&1; then
  record_blocker "PHASE8-VM-VALIDATE-GUESTFISH" "guestfish not found in PATH"
  echo "ERROR: guestfish is required for offline inspection" >&2
  exit 1
fi

"${FABRIC_REPO_ROOT}/ops/images/vm/validate/validate-qcow2.sh" --qcow2 "$qcow2"
"${FABRIC_REPO_ROOT}/ops/images/vm/validate/validate-cloud-init.sh" --qcow2 "$qcow2"
"${FABRIC_REPO_ROOT}/ops/images/vm/validate/validate-ssh-posture.sh" --qcow2 "$qcow2"
"${FABRIC_REPO_ROOT}/ops/images/vm/validate/validate-pkg-manifest.sh" --qcow2 "$qcow2"

meta=$(guestfish --ro -a "$qcow2" -i <<'EOF_GF'
is-file /etc/samakia-image/build-info.json
EOF_GF
)

if [[ "$meta" != "true" ]]; then
  echo "ERROR: /etc/samakia-image/build-info.json not found" >&2
  exit 1
fi
