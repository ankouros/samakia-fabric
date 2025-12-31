#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

require_cmd() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_cmd git
require_cmd rg

base_ref=""
if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
  base_ref="origin/${GITHUB_BASE_REF}"
elif git -C "${FABRIC_REPO_ROOT}" rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
  base_ref="@{upstream}"
elif git -C "${FABRIC_REPO_ROOT}" rev-parse --verify origin/main >/dev/null 2>&1; then
  base_ref="origin/main"
fi

changed_files=""
if [[ -n "${base_ref}" ]]; then
  changed_files+="$(git -C "${FABRIC_REPO_ROOT}" diff --name-only "${base_ref}...HEAD" || true)"
else
  if git -C "${FABRIC_REPO_ROOT}" rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    changed_files+="$(git -C "${FABRIC_REPO_ROOT}" diff --name-only HEAD~1..HEAD || true)"
  fi
fi

changed_files+="
$(git -C "${FABRIC_REPO_ROOT}" diff --name-only --cached || true)"
changed_files+="
$(git -C "${FABRIC_REPO_ROOT}" diff --name-only || true)"

# Normalize and de-duplicate
changed_files="$(printf '%s\n' "${changed_files}" | awk 'NF' | sort -u)"

if [[ -z "${changed_files}" ]]; then
  echo "policy-docs: no changes detected"
  exit 0
fi

needs_docs=0
if printf '%s\n' "${changed_files}" | rg -q -e '^\.github/workflows/' -e '^ops/policy/' -e '^ops/scripts/' -e '^Makefile$'; then
  needs_docs=1
fi

if [[ "${needs_docs}" -eq 0 ]]; then
  echo "policy-docs: no docs requirement triggered"
  exit 0
fi

if printf '%s\n' "${changed_files}" | rg -q -e '^OPERATIONS.md$' -e '^CHANGELOG.md$' -e '^REVIEW.md$' -e '^DECISIONS.md$'; then
  echo "policy-docs: docs updated"
  exit 0
fi

cat >&2 <<'EOT'
ERROR: workflow/script/Makefile changes detected but required docs were not updated.
Update at least one of:
  - OPERATIONS.md
  - CHANGELOG.md
  - REVIEW.md
  - DECISIONS.md
EOT
exit 1
