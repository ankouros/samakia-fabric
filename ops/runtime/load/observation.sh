#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

obs_path="${OBSERVATION_PATH:-${FABRIC_REPO_ROOT}/contracts/runtime-observation/observation.yml}"

if [[ ! -f "${obs_path}" ]]; then
  echo "ERROR: observation contract missing at ${obs_path}" >&2
  exit 1
fi

if [[ -z "${OUT_PATH:-}" ]]; then
  python3 - "${obs_path}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
print(json.dumps(data, indent=2, sort_keys=True))
PY
  exit 0
fi

python3 - "${obs_path}" "${OUT_PATH}" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
dest = Path(sys.argv[2])
data = json.loads(src.read_text())
dest.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
