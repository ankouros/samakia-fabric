#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


make -C "${FABRIC_REPO_ROOT}" hardening.checklist.render
make -C "${FABRIC_REPO_ROOT}" hardening.checklist.summary >/dev/null
