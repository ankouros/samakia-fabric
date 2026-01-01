#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

make -C "${FABRIC_REPO_ROOT}" hardening.checklist.render
make -C "${FABRIC_REPO_ROOT}" hardening.checklist.summary >/dev/null
