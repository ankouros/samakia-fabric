#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


policy_dir="${FABRIC_REPO_ROOT}/ops/policy"
policy_sh="${policy_dir}/policy.sh"

if [[ ! -f "${policy_sh}" ]]; then
  echo "ERROR: policy dispatcher missing: ${policy_sh}" >&2
  exit 1
fi

mapfile -t scripts < <(FABRIC_REPO_ROOT="${FABRIC_REPO_ROOT}" python3 - <<'PY'
import os
import re
from pathlib import Path

root = Path(os.environ["FABRIC_REPO_ROOT"])
policy_sh = root / "ops" / "policy" / "policy.sh"
text = policy_sh.read_text(encoding="utf-8")

block = re.search(r"scripts=\((.*?)\)\n\n", text, re.S)
if not block:
    raise SystemExit("failed to parse policy script list")

items = []
for line in block.group(1).splitlines():
    line = line.strip().strip('"')
    if not line:
        continue
    items.append(line)

for item in items:
    print(item)
PY
)

missing=0
has_go_live=0
for script in "${scripts[@]}"; do
  if [[ "${script}" == "policy-go-live.sh" ]]; then
    has_go_live=1
  fi
  path="${policy_dir}/${script}"
  if [[ ! -x "${path}" ]]; then
    echo "ERROR: policy script missing or not executable: ${path}" >&2
    missing=1
  fi
done

if [[ "${has_go_live}" -ne 1 ]]; then
  echo "ERROR: policy-go-live.sh is not wired into policy.sh" >&2
  missing=1
fi

if [[ "${missing}" -ne 0 ]]; then
  exit 1
fi

echo "PASS: policy gate inventory matches policy.sh"
