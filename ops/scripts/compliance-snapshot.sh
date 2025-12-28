#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${name}" >&2
    exit 1
  fi
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: missing required env var: ${name}" >&2
    exit 1
  fi
}

file_nonempty() {
  local path="$1"
  [[ -f "${path}" && -s "${path}" ]]
}

gpg_detach_sign_atomic() {
  local fingerprint="$1"
  local in_file="$2"
  local out_file="$3"

  local tmp
  tmp="$(mktemp)"
  if gpg --batch --yes --armor --local-user "${fingerprint}" --detach-sign -o "${tmp}" "${in_file}"; then
    if [[ ! -s "${tmp}" ]]; then
      rm -f "${tmp}"
      return 1
    fi
    mv -f "${tmp}" "${out_file}"
    return 0
  fi

  rm -f "${tmp}" || true
  return 1
}

gpg_sign_if_missing() {
  local fingerprint="$1"
  local in_file="$2"
  local out_file="$3"

  if file_nonempty "${out_file}"; then
    return 0
  fi

  gpg_detach_sign_atomic "${fingerprint}" "${in_file}" "${out_file}"
}

tsa_notarize_manifest() {
  local snapshot_dir="$1"
  local manifest_file="$2"
  local tsa_url="$3"
  local tsa_ca="$4"
  local tsa_policy="${5:-}"

  local tsr="${snapshot_dir}/manifest.sha256.tsr"
  local tsa_ca_dst="${snapshot_dir}/tsa-ca.pem"
  local tsa_meta="${snapshot_dir}/tsa-metadata.json"

  if [[ ! "${tsa_url}" =~ ^https:// ]]; then
    echo "ERROR: TSA URL must be https:// (strict TLS required): ${tsa_url}" >&2
    return 1
  fi

  if [[ -f "${tsr}" ]]; then
    echo "ERROR: TSA token already exists (immutable): ${tsr}" >&2
    return 1
  fi

  if [[ ! -f "${tsa_ca}" ]]; then
    echo "ERROR: TSA CA bundle not found: ${tsa_ca}" >&2
    return 1
  fi

  if [[ ! -f "${tsa_ca_dst}" ]]; then
    cp "${tsa_ca}" "${tsa_ca_dst}"
  fi

  local req
  req="$(mktemp)"
  local resp
  resp="$(mktemp)"

  if [[ -n "${tsa_policy}" ]]; then
    openssl ts -query -data "${manifest_file}" -sha256 -cert -policy "${tsa_policy}" -out "${req}" >/dev/null 2>&1
  else
    openssl ts -query -data "${manifest_file}" -sha256 -cert -out "${req}" >/dev/null 2>&1
  fi

  if ! curl -fsS \
    --cacert "${tsa_ca}" \
    -H "Content-Type: application/timestamp-query" \
    --data-binary "@${req}" \
    "${tsa_url}" \
    -o "${resp}"; then
    rm -f "${req}" "${resp}" || true
    echo "ERROR: TSA request failed (strict TLS enforced) for ${tsa_url}" >&2
    return 1
  fi

  if [[ ! -s "${resp}" ]]; then
    rm -f "${req}" "${resp}" || true
    echo "ERROR: TSA response is empty" >&2
    return 1
  fi

  mv -f "${resp}" "${tsr}"
  rm -f "${req}" || true

  if ! openssl ts -verify -data "${manifest_file}" -in "${tsr}" -CAfile "${tsa_ca_dst}" >/dev/null 2>&1; then
    echo "ERROR: TSA token verification failed for ${tsr}" >&2
    return 1
  fi

  local ts_utc
  ts_utc="$(
    openssl ts -reply -in "${tsr}" -text 2>/dev/null \
      | python3 -c 'import re,sys; text=sys.stdin.read(); m=re.search(r"(?m)^Time stamp:\\s*(.+?)\\s*$", text); print(m.group(1) if m else "unknown")'
  )"

  local tsr_sha256
  tsr_sha256="$(sha256sum "${tsr}" | awk '{print $1}')"

  export TSA_URL="${tsa_url}"
  export TSA_POLICY="${tsa_policy}"
  export TSA_TIMESTAMP="${ts_utc}"
  export TSR_SHA256="${tsr_sha256}"

  python3 - "${tsa_meta}" <<'PY'
import json
import os
import sys

out = sys.argv[1]

doc = {
  "tsa_url": os.environ["TSA_URL"],
  "tsa_policy": os.environ.get("TSA_POLICY") or None,
  "hash_algo": "sha256",
  "notarized_file": "manifest.sha256",
  "tsr_file": "manifest.sha256.tsr",
  "tsr_sha256": os.environ["TSR_SHA256"],
  "timestamp": os.environ["TSA_TIMESTAMP"],
}

with open(out, "w", encoding="utf-8") as f:
  json.dump(doc, f, indent=2, sort_keys=True)
  f.write("\\n")
PY

  return 0
}

ENV_NAME="${1:-}"
if [[ -z "${ENV_NAME}" ]]; then
  echo "Usage: $0 <terraform-env-name>" >&2
  echo "Example: $0 samakia-prod" >&2
  exit 2
fi

TF_ENV_DIR="${REPO_ROOT}/fabric-core/terraform/envs/${ENV_NAME}"
if [[ ! -d "${TF_ENV_DIR}" ]]; then
  echo "ERROR: Terraform env directory not found: ${TF_ENV_DIR}" >&2
  exit 1
fi

require_cmd terraform
require_cmd ansible-playbook
require_cmd python3
require_cmd git
require_cmd sha256sum
require_cmd find
require_cmd sort
require_cmd xargs
require_cmd gpg
require_cmd head
require_cmd awk
require_cmd mktemp
require_cmd mv
require_cmd rm

DUAL_CONTROL="${COMPLIANCE_DUAL_CONTROL:-}"
SNAPSHOT_DIR_OVERRIDE="${COMPLIANCE_SNAPSHOT_DIR:-}"

TSA_URL="${COMPLIANCE_TSA_URL:-}"
TSA_CA="${COMPLIANCE_TSA_CA:-}"
TSA_POLICY="${COMPLIANCE_TSA_POLICY:-}"
TSA_ENABLED=0

if [[ -n "${TSA_URL}" || -n "${TSA_CA}" || -n "${TSA_POLICY}" ]]; then
  require_env COMPLIANCE_TSA_URL
  require_env COMPLIANCE_TSA_CA
  if [[ ! -f "${TSA_CA}" ]]; then
    echo "ERROR: TSA CA bundle not found: ${TSA_CA}" >&2
    exit 1
  fi
  require_cmd curl
  require_cmd openssl
  TSA_ENABLED=1
fi

if [[ -z "${SNAPSHOT_DIR_OVERRIDE}" ]]; then
  require_env TF_VAR_pm_api_url
  require_env TF_VAR_pm_api_token_id
  require_env TF_VAR_pm_api_token_secret
fi

if [[ -z "${SNAPSHOT_DIR_OVERRIDE}" ]]; then
  # Guardrails: strict TLS and internal CA on runner host.
  bash "${REPO_ROOT}/fabric-ci/scripts/check-proxmox-ca-and-tls.sh"

  if [[ -z "${ALLOW_DIRTY_GIT:-}" ]]; then
    if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain=v1 2>/dev/null || true)" ]]; then
      echo "ERROR: working tree is dirty; compliance snapshots must correspond to a specific commit." >&2
      echo "Commit/stash changes or set ALLOW_DIRTY_GIT=1 (not recommended for compliance evidence)." >&2
      exit 1
    fi
  fi
fi

timestamp_utc="$(date -u +%Y%m%dT%H%M%SZ)"
commit_sha_full="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
commit_sha_short="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"

if [[ -n "${SNAPSHOT_DIR_OVERRIDE}" ]]; then
  snapshot_dir="${SNAPSHOT_DIR_OVERRIDE}"
else
  snapshot_dir="${REPO_ROOT}/compliance/${ENV_NAME}/snapshot-${timestamp_utc}"
fi
mkdir -p "${snapshot_dir}"

manifest="${snapshot_dir}/manifest.sha256"

main_tf="${TF_ENV_DIR}/main.tf"
template_version="$(
  python3 - "${main_tf}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8") if path.exists() else ""
m = re.search(r'(?m)^\s*lxc_rootfs_version\s*=\s*"([^"]+)"\s*$', text)
print(m.group(1) if m else "unknown")
PY
)"

template_ref="$(
  python3 - "${main_tf}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8") if path.exists() else ""
m = re.search(r'(?m)^\s*lxc_template\s*=\s*"([^"]+)"\s*$', text)
print(m.group(1) if m else "unknown")
PY
)"

if [[ -n "${SNAPSHOT_DIR_OVERRIDE}" ]]; then
  if [[ ! -f "${manifest}" ]]; then
    echo "ERROR: missing manifest in snapshot dir: ${manifest}" >&2
    exit 1
  fi
fi

if [[ -n "${SNAPSHOT_DIR_OVERRIDE}" ]]; then
  signing_mode="single"
  if [[ -f "${snapshot_dir}/DUAL_CONTROL_REQUIRED" ]]; then
    signing_mode="dual"
    require_env COMPLIANCE_GPG_KEYS
  else
    signing_mode="single"
    require_env COMPLIANCE_GPG_KEY
  fi

  gpg_fpr_a=""
  gpg_fpr_b=""

  if [[ "${signing_mode}" == "dual" ]]; then
    IFS=',' read -r key_a key_b extra <<<"${COMPLIANCE_GPG_KEYS}"
    if [[ -z "${key_a// /}" || -z "${key_b// /}" || -n "${extra:-}" ]]; then
      echo "ERROR: COMPLIANCE_GPG_KEYS must contain exactly two comma-separated key identifiers (fingerprints recommended)." >&2
      exit 1
    fi

    gpg_fpr_a="$(gpg --batch --with-colons --fingerprint "${key_a}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
    gpg_fpr_b="$(gpg --batch --with-colons --fingerprint "${key_b}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"

    if [[ -z "${gpg_fpr_a}" || -z "${gpg_fpr_b}" ]]; then
      echo "ERROR: unable to resolve required signing key fingerprint(s)." >&2
      exit 1
    fi

    # Export signer public keys for offline verification (public material only).
    if [[ ! -s "${snapshot_dir}/signer-publickey.a.asc" ]]; then
      gpg --batch --yes --armor --export "${gpg_fpr_a}" >"${snapshot_dir}/signer-publickey.a.asc"
    fi
    if [[ ! -s "${snapshot_dir}/signer-publickey.b.asc" ]]; then
      gpg --batch --yes --armor --export "${gpg_fpr_b}" >"${snapshot_dir}/signer-publickey.b.asc"
    fi

    signature_a="${snapshot_dir}/manifest.sha256.asc.a"
    signature_b="${snapshot_dir}/manifest.sha256.asc.b"

    sign_ok_a=0
    sign_ok_b=0
    set +e
    gpg_sign_if_missing "${gpg_fpr_a}" "${manifest}" "${signature_a}"
    sign_ok_a=$?
    gpg_sign_if_missing "${gpg_fpr_b}" "${manifest}" "${signature_b}"
    sign_ok_b=$?
    set -e

    if [[ "${sign_ok_a}" -ne 0 || "${sign_ok_b}" -ne 0 ]]; then
      printf '%s\n' "INCOMPLETE: missing one or more signatures; required: ${signature_a} and ${signature_b}" >"${snapshot_dir}/SIGNING_INCOMPLETE"
      if [[ -z "${ALLOW_PARTIAL_SIGNATURE:-}" ]]; then
        echo "ERROR: dual-control signing incomplete (set ALLOW_PARTIAL_SIGNATURE=1 only for staged signing workflows)." >&2
        exit 1
      fi
    fi

    if [[ -f "${signature_a}" && -f "${signature_b}" ]]; then
      if [[ "${TSA_ENABLED}" -eq 1 ]]; then
        if ! tsa_notarize_manifest "${snapshot_dir}" "${manifest}" "${TSA_URL}" "${TSA_CA}" "${TSA_POLICY}"; then
          printf '%s\n' "TSA_NOTARIZATION_FAILED" >"${snapshot_dir}/TSA_NOTARIZATION_FAILED"
          exit 1
        fi
      fi
      chmod -R a-w "${snapshot_dir}" || true
    fi

    echo "OK: signed existing snapshot manifest (dual-control): ${snapshot_dir}"
    echo "OK: signatures: ${signature_a} ${signature_b}"
    exit 0
  fi

  gpg_fpr_a="$(gpg --batch --with-colons --fingerprint "${COMPLIANCE_GPG_KEY}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
  if [[ -z "${gpg_fpr_a}" ]]; then
    echo "ERROR: unable to resolve required signing key fingerprint." >&2
    exit 1
  fi

  # Export signer public key for offline verification (public material only).
  if [[ ! -s "${snapshot_dir}/signer-publickey.asc" ]]; then
    gpg --batch --yes --armor --export "${gpg_fpr_a}" >"${snapshot_dir}/signer-publickey.asc"
  fi

  signature_single="${snapshot_dir}/manifest.sha256.asc"
  gpg_sign_if_missing "${gpg_fpr_a}" "${manifest}" "${signature_single}"

  if [[ "${TSA_ENABLED}" -eq 1 ]]; then
    if ! tsa_notarize_manifest "${snapshot_dir}" "${manifest}" "${TSA_URL}" "${TSA_CA}" "${TSA_POLICY}"; then
      printf '%s\n' "TSA_NOTARIZATION_FAILED" >"${snapshot_dir}/TSA_NOTARIZATION_FAILED"
      exit 1
    fi
  fi

  chmod -R a-w "${snapshot_dir}" || true

  echo "OK: signed existing snapshot manifest: ${snapshot_dir}"
  echo "OK: signature: ${signature_single}"
  exit 0
fi

versions_txt="${snapshot_dir}/versions.txt"
{
  echo "timestamp_utc=${timestamp_utc}"
  echo "env=${ENV_NAME}"
  echo "git_commit=${commit_sha_full}"
  echo
  echo "terraform_version:"
  terraform version || true
  echo
  echo "ansible_version:"
  ansible-playbook --version || true
  echo
  echo "python_version:"
  python3 --version || true
  echo
  echo "gpg_version:"
  gpg --version | head -n 2 || true
} >"${versions_txt}"

terraform_version_json="$(
  terraform version -json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), separators=(",", ":")))'
)"

ansible_version_line="$(ansible-playbook --version 2>/dev/null | head -n 1 | tr -d '\r' || true)"

proxmox_cluster_json="{}"
if [[ -z "${SNAPSHOT_DIR_OVERRIDE}" ]]; then
  proxmox_cluster_json="$(
    python3 - <<'PY'
import json
import os
import sys
import urllib.request

api_url = os.environ.get("TF_VAR_pm_api_url", "").rstrip("/")
token_id = os.environ.get("TF_VAR_pm_api_token_id", "")
token_secret = os.environ.get("TF_VAR_pm_api_token_secret", "")
url = f"{api_url}/cluster/status"

req = urllib.request.Request(
    url,
    headers={"Authorization": f"PVEAPIToken={token_id}={token_secret}"},
)

with urllib.request.urlopen(req, timeout=5) as resp:
    payload = json.loads(resp.read().decode("utf-8"))

cluster_name = None
quorate = None
node_count = 0

for item in payload.get("data", []):
    if item.get("type") == "cluster":
        cluster_name = item.get("name") or item.get("cluster") or item.get("id")
        quorate = item.get("quorate")
    if item.get("type") == "node":
        node_count += 1

print(
    json.dumps(
        {
            "cluster_name": cluster_name or "unknown",
            "quorate": bool(quorate) if quorate is not None else None,
            "node_count": node_count,
        }
    )
)
PY
  )"
fi

signing_mode="single"
gpg_fpr_a=""
gpg_fpr_b=""
signing_keys_json="[]"

if [[ -n "${DUAL_CONTROL}" ]]; then
  signing_mode="dual"
  require_env COMPLIANCE_GPG_KEYS

  IFS=',' read -r key_a key_b extra <<<"${COMPLIANCE_GPG_KEYS}"
  if [[ -z "${key_a// /}" || -z "${key_b// /}" || -n "${extra:-}" ]]; then
    echo "ERROR: COMPLIANCE_GPG_KEYS must contain exactly two comma-separated key identifiers (fingerprints recommended)." >&2
    exit 1
  fi

  gpg_fpr_a="$(gpg --batch --with-colons --fingerprint "${key_a}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
  gpg_fpr_b="$(gpg --batch --with-colons --fingerprint "${key_b}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"

  signing_keys_json="$(
    python3 - "${gpg_fpr_a}" "${gpg_fpr_b}" <<'PY'
import json
import sys
print(json.dumps([sys.argv[1], sys.argv[2]]))
PY
  )"
else
  require_env COMPLIANCE_GPG_KEY
  gpg_fpr_a="$(gpg --batch --with-colons --fingerprint "${COMPLIANCE_GPG_KEY}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
  signing_keys_json="$(
    python3 - "${gpg_fpr_a}" <<'PY'
import json
import sys
print(json.dumps([sys.argv[1]]))
PY
  )"
fi

if [[ -z "${gpg_fpr_a}" || ( "${signing_mode}" == "dual" && -z "${gpg_fpr_b}" ) ]]; then
  echo "ERROR: unable to resolve required signing key fingerprint(s)." >&2
  exit 1
fi

metadata_json="${snapshot_dir}/metadata.json"
export PROXMOX_CLUSTER_JSON="${proxmox_cluster_json}"
export SNAPSHOT_TIMESTAMP_UTC="${timestamp_utc}"
export SNAPSHOT_ENV="${ENV_NAME}"
export SNAPSHOT_GIT_COMMIT="${commit_sha_full}"
export SNAPSHOT_GIT_COMMIT_SHORT="${commit_sha_short}"
export SNAPSHOT_TEMPLATE_VERSION="${template_version}"
export SNAPSHOT_TEMPLATE_REF="${template_ref}"
export TERRAFORM_VERSION_JSON="${terraform_version_json}"
export ANSIBLE_VERSION_LINE="${ansible_version_line}"
export SIGNING_MODE="${signing_mode}"
export SIGNING_KEYS_JSON="${signing_keys_json}"

python3 - "${metadata_json}" <<'PY'
import json
import os
import sys

out = sys.argv[1]

proxmox = json.loads(os.environ["PROXMOX_CLUSTER_JSON"])

doc = {
    "timestamp_utc": os.environ["SNAPSHOT_TIMESTAMP_UTC"],
    "environment": os.environ["SNAPSHOT_ENV"],
    "git_commit": os.environ["SNAPSHOT_GIT_COMMIT"],
    "git_commit_short": os.environ["SNAPSHOT_GIT_COMMIT_SHORT"],
    "template_version": os.environ["SNAPSHOT_TEMPLATE_VERSION"],
    "template_ref": os.environ["SNAPSHOT_TEMPLATE_REF"],
    "terraform_version_json": json.loads(os.environ["TERRAFORM_VERSION_JSON"]),
    "ansible_version": os.environ["ANSIBLE_VERSION_LINE"],
    "proxmox": proxmox,
    "signing": {
        "tool": "gpg",
        "mode": os.environ["SIGNING_MODE"],
        "required_fingerprints": json.loads(os.environ["SIGNING_KEYS_JSON"]),
    },
}

with open(out, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\\n")
PY

if [[ -z "${SNAPSHOT_DIR_OVERRIDE}" ]]; then
  # Invoke the existing drift audit logic, but force it to write into this snapshot.
  export AUDIT_TIMESTAMP_UTC="${timestamp_utc}"
  export AUDIT_OUT_DIR="${snapshot_dir}"
  export FABRIC_TERRAFORM_ENV="${ENV_NAME}"

  bash "${REPO_ROOT}/ops/scripts/drift-audit.sh" "${ENV_NAME}" >/dev/null
fi

# Normalize filenames for auditors (keep originals too).
if [[ -f "${snapshot_dir}/ansible-harden-check.txt" ]]; then
  cp "${snapshot_dir}/ansible-harden-check.txt" "${snapshot_dir}/ansible-check.diff"
fi

if [[ -z "${SNAPSHOT_DIR_OVERRIDE}" ]]; then
  if [[ "${signing_mode}" == "dual" ]]; then
    printf '%s\n' "DUAL_CONTROL_REQUIRED" >"${snapshot_dir}/DUAL_CONTROL_REQUIRED"
    gpg --batch --yes --armor --export "${gpg_fpr_a}" >"${snapshot_dir}/signer-publickey.a.asc"
    gpg --batch --yes --armor --export "${gpg_fpr_b}" >"${snapshot_dir}/signer-publickey.b.asc"

    python3 - "${snapshot_dir}/approvals.json" "${gpg_fpr_a}" "${gpg_fpr_b}" <<'PY'
import json
import sys

out = sys.argv[1]
fpr_a = sys.argv[2]
fpr_b = sys.argv[3]

doc = {
    "required_signatures": [
        {"role": "custodian_a", "fingerprint": fpr_a, "signature_file": "manifest.sha256.asc.a"},
        {"role": "custodian_b", "fingerprint": fpr_b, "signature_file": "manifest.sha256.asc.b"},
    ]
}

with open(out, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\n")
PY
  else
    # Export signer public key for offline verification (public material only).
    gpg --batch --yes --armor --export "${gpg_fpr_a}" >"${snapshot_dir}/signer-publickey.asc"
  fi
fi

# Include TSA trust anchor (public) in the snapshot when enabled.
if [[ "${TSA_ENABLED}" -eq 1 && -z "${SNAPSHOT_DIR_OVERRIDE}" ]]; then
  if [[ ! -f "${snapshot_dir}/tsa-ca.pem" ]]; then
    cp "${TSA_CA}" "${snapshot_dir}/tsa-ca.pem"
  fi
fi

# Produce a deterministic manifest (sha256) over snapshot contents.
(
  cd "${snapshot_dir}"
  find . \
    -path './legal-hold' -prune -o \
    -type f \
    ! -name 'manifest.sha256' \
    ! -name 'manifest.sha256.asc' \
    ! -name 'manifest.sha256.asc.a' \
    ! -name 'manifest.sha256.asc.b' \
    ! -name 'manifest.sha256.tsr' \
    ! -name 'tsa-metadata.json' \
    -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >manifest.sha256
)

signature_a="${snapshot_dir}/manifest.sha256.asc.a"
signature_b="${snapshot_dir}/manifest.sha256.asc.b"
signature_single="${snapshot_dir}/manifest.sha256.asc"

sign_ok_a=0
sign_ok_b=0

if [[ "${signing_mode}" == "dual" ]]; then
  set +e
  gpg_sign_if_missing "${gpg_fpr_a}" "${manifest}" "${signature_a}"
  sign_ok_a=$?
  gpg_sign_if_missing "${gpg_fpr_b}" "${manifest}" "${signature_b}"
  sign_ok_b=$?
  set -e

  if [[ "${sign_ok_a}" -ne 0 || "${sign_ok_b}" -ne 0 ]]; then
    printf '%s\n' "INCOMPLETE: missing one or more signatures; required: ${signature_a} and ${signature_b}" >"${snapshot_dir}/SIGNING_INCOMPLETE"
    if [[ -z "${ALLOW_PARTIAL_SIGNATURE:-}" ]]; then
      echo "ERROR: dual-control signing incomplete (set ALLOW_PARTIAL_SIGNATURE=1 only for staged signing workflows)." >&2
      exit 1
    fi
  fi
else
  gpg_sign_if_missing "${gpg_fpr_a}" "${manifest}" "${signature_single}"
fi

if [[ "${signing_mode}" != "dual" || ( -f "${signature_a}" && -f "${signature_b}" ) ]]; then
  if [[ "${TSA_ENABLED}" -eq 1 ]]; then
    if ! tsa_notarize_manifest "${snapshot_dir}" "${manifest}" "${TSA_URL}" "${TSA_CA}" "${TSA_POLICY}"; then
      printf '%s\n' "TSA_NOTARIZATION_FAILED" >"${snapshot_dir}/TSA_NOTARIZATION_FAILED"
      exit 1
    fi
  fi

  # Make the snapshot harder to tamper with accidentally (reversible).
  chmod -R a-w "${snapshot_dir}" || true
fi

echo "OK: wrote signed compliance snapshot: ${snapshot_dir}"
if [[ "${signing_mode}" == "dual" ]]; then
  echo "OK: signatures: ${signature_a} ${signature_b}"
else
  echo "OK: signature: ${signature_single}"
fi

exit 0
