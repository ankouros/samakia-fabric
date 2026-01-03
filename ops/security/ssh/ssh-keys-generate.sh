#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  ssh-keys-generate.sh --name <key-name> [--dir <path>]

Options:
  --name <key-name>     Key name (required)
  --dir <path>          Target directory (default: ~/.config/samakia-fabric/ssh-keys/<name>)

Env:
  SSH_KEY_PASSPHRASE        Optional passphrase (avoid empty for production)
  SSH_KEY_PASSPHRASE_FILE   Optional passphrase file

Notes:
  - Private keys are written only to the runner local filesystem.
  - Public key fingerprint is printed; private key material is not.
EOT
}

name=""
base_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      name="$2"
      shift 2
      ;;
    --dir)
      base_dir="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${name}" ]]; then
  echo "ERROR: --name is required" >&2
  usage
  exit 2
fi

if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "ERROR: ssh-keygen not found" >&2
  exit 1
fi

if [[ -z "${base_dir}" ]]; then
  base_dir="${HOME}/.config/samakia-fabric/ssh-keys/${name}"
fi

mkdir -p "${base_dir}"
chmod 700 "${base_dir}"

key_path="${base_dir}/${name}"

if [[ -f "${key_path}" || -f "${key_path}.pub" ]]; then
  echo "ERROR: key already exists: ${key_path}" >&2
  exit 2
fi

passphrase=""
if [[ -n "${SSH_KEY_PASSPHRASE_FILE:-}" ]]; then
  if [[ ! -f "${SSH_KEY_PASSPHRASE_FILE}" ]]; then
    echo "ERROR: SSH_KEY_PASSPHRASE_FILE not found: ${SSH_KEY_PASSPHRASE_FILE}" >&2
    exit 2
  fi
  passphrase="$(cat "${SSH_KEY_PASSPHRASE_FILE}")"
elif [[ -n "${SSH_KEY_PASSPHRASE:-}" ]]; then
  passphrase="${SSH_KEY_PASSPHRASE}"
fi

ssh-keygen -t ed25519 -f "${key_path}" -N "${passphrase}" >/dev/null
chmod 600 "${key_path}"
chmod 644 "${key_path}.pub"

fingerprint="$(ssh-keygen -lf "${key_path}.pub" | awk '{print $2}')"

cat <<EOT
Key generated:
- Private key: ${key_path}
- Public key:  ${key_path}.pub
- Fingerprint: ${fingerprint}
EOT
