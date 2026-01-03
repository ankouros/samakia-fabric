#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOT'
Usage:
  ollama.sh --text <value> --model <name> [--out <path>]
  ollama.sh --text-file <path> --model <name> [--out <path>]
EOT
}

text=""
text_file=""
model=""
out_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)
      text="$2"
      shift 2
      ;;
    --text-file)
      text_file="$2"
      shift 2
      ;;
    --model)
      model="$2"
      shift 2
      ;;
    --out)
      out_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -n "${text_file}" ]]; then
  if [[ ! -f "${text_file}" ]]; then
    echo "ERROR: text file not found: ${text_file}" >&2
    exit 1
  fi
  text="$(cat "${text_file}")"
fi

if [[ -z "${text}" || -z "${model}" ]]; then
  usage
  exit 2
fi

index_mode="${INDEX_MODE:-offline}"
base_url="${OLLAMA_BASE_URL:-}"

if [[ -z "${base_url}" ]]; then
  base_url="$(PROVIDER_FILE="${PROVIDER_FILE:-}" python3 - <<'PY'
import os
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"ERROR: missing dependency for Ollama config: {exc}")

provider_path = os.environ.get("PROVIDER_FILE") or "contracts/ai/provider.yml"
path = Path(provider_path)
if not path.exists():
    raise SystemExit(f"ERROR: provider contract not found: {provider_path}")
provider = yaml.safe_load(path.read_text(encoding="utf-8"))
print(provider.get("base_url", ""))
PY
)"
fi

if [[ "${index_mode}" != "live" || "${OLLAMA_ENABLE:-0}" != "1" ]]; then
  EMBED_TEXT="${text}" EMBED_MODEL="${model}" OUT_PATH="${out_path}" python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

text = os.environ["EMBED_TEXT"]
model = os.environ["EMBED_MODEL"]
out_path = os.environ.get("OUT_PATH")

h = hashlib.sha256(text.encode("utf-8")).digest()
vector = [round(b / 255.0, 6) for b in h[:8]]

payload = {
    "model": model,
    "embedding": vector,
    "embedding_mode": "stub",
}

if out_path:
    Path(out_path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
else:
    print(json.dumps(payload, indent=2, sort_keys=True))
PY
  exit 0
fi

attempt=1
max_attempts=3
sleep_seconds=1

while [[ "${attempt}" -le "${max_attempts}" ]]; do
  if response="$(EMBED_MODEL="${model}" EMBED_TEXT="${text}" \
    curl -sS --fail -X POST "${base_url}/api/embeddings" \
    -H 'Content-Type: application/json' \
    -d "$(EMBED_MODEL="${model}" EMBED_TEXT="${text}" python3 - <<'PY'
import json
import os

print(json.dumps({"model": os.environ["EMBED_MODEL"], "prompt": os.environ["EMBED_TEXT"]}))
PY
)")"; then
    break
  fi
  if [[ "${attempt}" -eq "${max_attempts}" ]]; then
    echo "ERROR: Ollama embeddings request failed after ${max_attempts} attempts" >&2
    exit 1
  fi
  sleep "${sleep_seconds}"
  attempt=$((attempt + 1))
  sleep_seconds=$((sleep_seconds + 1))
done

OUT_PATH="${out_path}" RESPONSE="${response}" python3 - <<'PY'
import json
import os
from pathlib import Path

response = json.loads(os.environ["RESPONSE"])
embedding = response.get("embedding")

payload = {
    "model": response.get("model"),
    "embedding": embedding,
    "embedding_mode": "ollama",
}

out_path = os.environ.get("OUT_PATH")
if out_path:
    Path(out_path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
else:
    print(json.dumps(payload, indent=2, sort_keys=True))
PY
