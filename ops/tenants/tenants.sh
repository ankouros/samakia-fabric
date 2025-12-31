#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

TENANTS_ROOT="${FABRIC_REPO_ROOT}/contracts/tenants/examples"

usage() {
  cat <<'EOF'
Usage: tenants.sh <command> [args]

Commands:
  list
  validate <tenant-id|all>
  evidence <tenant-id|all>
  doctor
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

cmd="$1"
shift || true

case "${cmd}" in
  list)
    if [[ ! -d "${TENANTS_ROOT}" ]]; then
      echo "ERROR: tenant examples directory not found: ${TENANTS_ROOT}" >&2
      exit 1
    fi
    find "${TENANTS_ROOT}" -maxdepth 1 -mindepth 1 -type d -printf "%f\n" | sort
    ;;
  validate)
    tenant="${1:-all}"
    if [[ "${tenant}" == "all" ]]; then
      "${FABRIC_REPO_ROOT}/ops/tenants/validate.sh"
      "${FABRIC_REPO_ROOT}/ops/tenants/validate-policies.sh"
      "${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh"
      exit 0
    fi
    if [[ ! -d "${TENANTS_ROOT}/${tenant}" ]]; then
      echo "ERROR: tenant not found: ${tenant}" >&2
      exit 1
    fi
    "${FABRIC_REPO_ROOT}/ops/tenants/validate.sh"
    "${FABRIC_REPO_ROOT}/ops/tenants/validate-policies.sh"
    "${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh"
    ;;
  evidence)
    tenant="${1:-all}"
    TENANT="${tenant}" "${FABRIC_REPO_ROOT}/ops/tenants/evidence.sh"
    ;;
  doctor)
    missing=0
    for path in \
      "${FABRIC_REPO_ROOT}/contracts/tenants/_schema" \
      "${FABRIC_REPO_ROOT}/contracts/tenants/_templates" \
      "${FABRIC_REPO_ROOT}/contracts/tenants/examples" \
      "${FABRIC_REPO_ROOT}/ops/tenants/validate.sh" \
      "${FABRIC_REPO_ROOT}/ops/tenants/validate-policies.sh" \
      "${FABRIC_REPO_ROOT}/ops/tenants/validate-consumer-bindings.sh"
    do
      if [[ ! -e "${path}" ]]; then
        echo "MISSING: ${path}"
        missing=1
      fi
    done
    if [[ "${missing}" -eq 0 ]]; then
      echo "PASS: tenant tooling present"
    else
      exit 1
    fi
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
