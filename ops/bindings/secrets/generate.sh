#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


shape="${1:-}"
if [[ -z "${shape}" ]]; then
  echo "ERROR: usage: generate.sh <shape>" >&2
  exit 2
fi

python3 - <<'PY' "${shape}"
import json
import secrets
import string
import sys

shape = sys.argv[1]

alphabet = string.ascii_letters + string.digits

def rand_token(length=24):
    return "".join(secrets.choice(alphabet) for _ in range(length))

if shape == "postgres":
    payload = {
        "username": f"pg_{rand_token(8).lower()}",
        "password": rand_token(24),
        "database": "app",
        "sslmode": "require",
        "ca_ref": "ca/internal"
    }
elif shape == "mariadb":
    payload = {
        "username": f"mdb_{rand_token(8).lower()}",
        "password": rand_token(24),
        "database": "app",
        "tls_required": True,
        "ca_ref": "ca/internal"
    }
elif shape == "rabbitmq":
    payload = {
        "username": f"rmq_{rand_token(8).lower()}",
        "password": rand_token(24),
        "vhost": "/",
        "tls_required": True,
        "ca_ref": "ca/internal"
    }
elif shape == "dragonfly":
    payload = {
        "password": rand_token(24),
        "tenant_key_prefix": "tenant:",
        "tls_required": True,
        "ca_ref": "ca/internal"
    }
elif shape == "qdrant":
    payload = {
        "api_key": rand_token(32),
        "collection_prefix": "tenant_",
        "tls_required": True,
        "ca_ref": "ca/internal"
    }
else:
    raise SystemExit(f"ERROR: unsupported shape: {shape}")

print(json.dumps(payload, sort_keys=True))
PY
