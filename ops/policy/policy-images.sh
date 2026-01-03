#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

bash "${FABRIC_REPO_ROOT}/ops/images/validate/validate-pinning.sh"
bash "${FABRIC_REPO_ROOT}/ops/images/validate/validate-apt-snapshot.sh"
bash "${FABRIC_REPO_ROOT}/ops/images/validate/validate-provenance.sh"
