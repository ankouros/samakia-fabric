#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  materialize.sh TENANT=<id|all>

Environment:
  BIND_SECRETS_BACKEND=file|vault (default: file)
  MATERIALIZE_EXECUTE=1 to perform writes (default: dry-run)
  BIND_SECRET_INPUT_FILE=<path> (JSON map of secret_ref -> object) for operator_input
  SECRETS_GENERATE=1 to allow generated credentials
  SECRETS_GENERATE_ALLOWLIST=<comma-separated tenants>
  VAULT_ENABLE=1 (required for vault_readonly source)
  EVIDENCE_SIGN=1 EVIDENCE_SIGN_KEY=<id> (required for prod)
  MAINT_WINDOW_START/MAINT_WINDOW_END (required for prod)
EOT
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

tenant_filter="${TENANT:-all}"
backend="${BIND_SECRETS_BACKEND:-file}"
backend_script="${FABRIC_REPO_ROOT}/ops/bindings/secrets/backends/${backend}.sh"
file_backend="${FABRIC_REPO_ROOT}/ops/bindings/secrets/backends/file.sh"
vault_backend="${FABRIC_REPO_ROOT}/ops/bindings/secrets/backends/vault.sh"

if [[ ! -x "${backend_script}" ]]; then
  echo "ERROR: secrets backend not found or not executable: ${backend_script}" >&2
  exit 2
fi
if [[ ! -x "${file_backend}" ]]; then
  echo "ERROR: file backend not found or not executable: ${file_backend}" >&2
  exit 2
fi
if [[ ! -x "${vault_backend}" ]]; then
  echo "ERROR: vault backend not found or not executable: ${vault_backend}" >&2
  exit 2
fi

bindings_root="${FABRIC_REPO_ROOT}/contracts/bindings/tenants"
mapfile -t bindings < <(find "${bindings_root}" -type f -name "*.binding.yml" -print | sort)
if [[ ${#bindings[@]} -eq 0 ]]; then
  echo "ERROR: no binding contracts found under ${bindings_root}" >&2
  exit 1
fi

entries_tsv=$(BINDINGS_LIST="$(printf '%s\n' "${bindings[@]}")" TENANT_FILTER="${tenant_filter}" python3 - <<'PY'
import os
from pathlib import Path
import yaml

bindings = [Path(p) for p in os.environ.get("BINDINGS_LIST", "").splitlines() if p]
flt = os.environ.get("TENANT_FILTER", "all")

rows = []
for binding in bindings:
    data = yaml.safe_load(binding.read_text())
    meta = data.get("metadata", {})
    tenant = meta.get("tenant") or ""
    env = meta.get("env") or ""
    if flt != "all" and tenant != flt:
        continue
    for consumer in data.get("spec", {}).get("consumers", []):
        secret_ref = consumer.get("secret_ref") or ""
        secret_shape = consumer.get("secret_shape") or ""
        source = consumer.get("credential_source") or ""
        provider = consumer.get("provider") or ""
        rows.append((tenant, env, secret_ref, secret_shape, source, provider))

for row in rows:
    print("\t".join(row))
PY
)

if [[ -z "${entries_tsv}" ]]; then
  echo "ERROR: no secrets to materialize for tenant filter ${tenant_filter}" >&2
  exit 1
fi

execute="${MATERIALIZE_EXECUTE:-0}"
if [[ "${execute}" != "1" ]]; then
  echo "INFO: dry-run mode (set MATERIALIZE_EXECUTE=1 to write secrets)"
fi

if [[ "${execute}" == "1" && "${CI:-0}" == "1" ]]; then
  echo "ERROR: secrets materialization execute is not allowed in CI" >&2
  exit 2
fi

execute_blocked_reason=""
if [[ "${execute}" == "1" && "${backend}" != "file" ]]; then
  execute_blocked_reason="backend_not_supported"
fi

prod_guard_failed="0"
prod_guard_reason=""
if [[ "${execute}" == "1" ]] && grep -q $'\tprod\t' <<<"${entries_tsv}"; then
  if [[ "${EVIDENCE_SIGN:-0}" != "1" || -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
    prod_guard_failed="1"
    prod_guard_reason="prod_signing_required"
  else
    if ! bash "${FABRIC_REPO_ROOT}/ops/tenants/execute/change-window.sh"; then
      prod_guard_failed="1"
      prod_guard_reason="change_window_failed"
    fi
  fi
fi

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
base_dir="${FABRIC_REPO_ROOT}/evidence/bindings"
entries_file="$(mktemp)"
results_file="$(mktemp)"
trap 'rm -f "${entries_file}" "${results_file}"' EXIT
printf '%s\n' "${entries_tsv}" >"${entries_file}"

input_file="${BIND_SECRET_INPUT_FILE:-}"

has_error="0"
while IFS=$'\t' read -r tenant env secret_ref secret_shape source provider; do
  status="skipped"
  action="dry-run"
  reason="dry-run"

  if [[ -z "${secret_ref}" || -z "${secret_shape}" || -z "${source}" ]]; then
    status="error"
    reason="missing_fields"
  elif [[ "${execute}" == "1" ]]; then
    action="materialize"
    if [[ -n "${execute_blocked_reason}" ]]; then
      status="error"
      reason="${execute_blocked_reason}"
    elif [[ "${env}" == "prod" && "${prod_guard_failed}" == "1" ]]; then
      status="error"
      reason="${prod_guard_reason}"
    else
      tmp_file=""
      case "${source}" in
        operator_input)
          if [[ -z "${input_file}" ]]; then
            status="error"
            reason="input_file_missing"
          elif [[ ! -f "${input_file}" ]]; then
            status="error"
            reason="input_file_not_found"
          else
            tmp_file="$(mktemp)"
            if ! python3 - "${input_file}" "${secret_ref}" >"${tmp_file}" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
key = sys.argv[2]

data = json.loads(src.read_text())
if key not in data:
    raise SystemExit(f"ERROR: secret_ref not found in input file: {key}")

payload = data[key]
if not isinstance(payload, dict):
    raise SystemExit("ERROR: secret payload must be an object")

print(json.dumps(payload, sort_keys=True))
PY
            then
              status="error"
              reason="input_lookup_failed"
              rm -f "${tmp_file}"
              tmp_file=""
            fi
          fi
          ;;
        existing_ref)
          if ! "${backend_script}" get "${secret_ref}" >/dev/null 2>&1; then
            status="error"
            reason="existing_ref_missing"
          else
            status="ok"
            reason="existing_ref"
          fi
          ;;
        generated)
          if [[ "${SECRETS_GENERATE:-0}" != "1" ]]; then
            status="error"
            reason="generate_disabled"
          elif [[ -z "${SECRETS_GENERATE_ALLOWLIST:-}" ]] || ! grep -q "\b${tenant}\b" <<<"${SECRETS_GENERATE_ALLOWLIST//,/ }"; then
            status="error"
            reason="generate_not_allowlisted"
          else
            tmp_file="$(mktemp)"
            if ! bash "${FABRIC_REPO_ROOT}/ops/bindings/secrets/generate.sh" "${secret_shape}" >"${tmp_file}"; then
              status="error"
              reason="generate_failed"
              rm -f "${tmp_file}"
              tmp_file=""
            fi
          fi
          ;;
        vault_readonly)
          if [[ "${VAULT_ENABLE:-0}" != "1" ]]; then
            status="error"
            reason="vault_disabled"
          elif [[ "${backend}" != "file" ]]; then
            status="error"
            reason="vault_requires_file"
          else
            tmp_file="$(mktemp)"
            if ! "${vault_backend}" get "${secret_ref}" >"${tmp_file}"; then
              status="error"
              reason="vault_lookup_failed"
              rm -f "${tmp_file}"
              tmp_file=""
            fi
          fi
          ;;
        *)
          status="error"
          reason="unsupported_source"
          ;;
      esac

      if [[ "${status}" == "skipped" ]]; then
        status="ok"
        reason="executed"
      fi

      if [[ "${status}" == "ok" && -n "${tmp_file}" ]]; then
        if bash "${file_backend}" put "${secret_ref}" "${tmp_file}"; then
          reason="executed"
        else
          status="error"
          reason="backend_write_failed"
        fi
        rm -f "${tmp_file}"
      fi
    fi
  fi

  if [[ "${status}" == "error" ]]; then
    has_error="1"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${tenant}" "${env}" "${secret_ref}" "${secret_shape}" "${source}" "${provider}" "${status}" "${action}" "${reason}" \
    >>"${results_file}"

done <<< "${entries_tsv}"

tenant_dirs=$(python3 - <<'PY' "${entries_file}" "${results_file}" "${base_dir}" "${stamp}" "${execute}" "${backend}" "${tenant_filter}"
import json
import sys
from pathlib import Path

entries_file = Path(sys.argv[1])
results_file = Path(sys.argv[2])
base_dir = Path(sys.argv[3])
stamp = sys.argv[4]
execute = sys.argv[5] == "1"
backend = sys.argv[6]
tenant_filter = sys.argv[7]

entries = []
for line in entries_file.read_text().splitlines():
    tenant, env, secret_ref, shape, source, provider = line.split("\t")
    entries.append({
        "tenant": tenant,
        "env": env,
        "secret_ref": secret_ref,
        "secret_shape": shape,
        "credential_source": source,
        "provider": provider,
    })

results = []
for line in results_file.read_text().splitlines():
    tenant, env, secret_ref, shape, source, provider, status, action, reason = line.split("\t")
    results.append({
        "tenant": tenant,
        "env": env,
        "secret_ref": secret_ref,
        "secret_shape": shape,
        "credential_source": source,
        "provider": provider,
        "status": status,
        "action": action,
        "reason": reason,
    })

if not entries:
    tenant_name = tenant_filter if tenant_filter != "all" else "all"
    tdir = base_dir / tenant_name / stamp / "secrets"
    tdir.mkdir(parents=True, exist_ok=True)
    (tdir / "request.json").write_text(json.dumps({"requested": []}, indent=2, sort_keys=True) + "\n")
    (tdir / "decision.json").write_text(json.dumps({"results": []}, indent=2, sort_keys=True) + "\n")
    (tdir / "secret_refs.json").write_text(json.dumps({"refs": []}, indent=2, sort_keys=True) + "\n")
    (tdir / "redaction_report.md").write_text(
        "# Redaction Report\n\nNo secret values stored; request and decision files contain only references.\n"
    )
    (tdir / "report.md").write_text(
        "# Binding Secret Materialization\n\n"
        f"Timestamp (UTC): {stamp}\n"
        f"Tenant: {tenant_name}\n"
        f"Backend: {backend}\n"
        f"Mode: {'execute' if execute else 'dry-run'}\n\n"
        "No entries found.\n"
    )
    print(tdir)
    sys.exit(0)

by_tenant = {}
for entry in entries:
    by_tenant.setdefault(entry["tenant"], {"entries": [], "results": []})
    by_tenant[entry["tenant"]]["entries"].append(entry)

for result in results:
    by_tenant.setdefault(result["tenant"], {"entries": [], "results": []})
    by_tenant[result["tenant"]]["results"].append(result)

for tenant in sorted(by_tenant.keys()):
    tdir = base_dir / tenant / stamp / "secrets"
    tdir.mkdir(parents=True, exist_ok=True)
    entry_block = by_tenant[tenant]["entries"]
    result_block = by_tenant[tenant]["results"]

    request = {"requested": entry_block}
    decision = {"results": result_block}
    refs = {
        "refs": [
            {
                "tenant": e["tenant"],
                "env": e["env"],
                "secret_ref": e["secret_ref"],
                "secret_shape": e["secret_shape"],
            }
            for e in entry_block
        ]
    }

    (tdir / "request.json").write_text(json.dumps(request, indent=2, sort_keys=True) + "\n")
    (tdir / "decision.json").write_text(json.dumps(decision, indent=2, sort_keys=True) + "\n")
    (tdir / "secret_refs.json").write_text(json.dumps(refs, indent=2, sort_keys=True) + "\n")
    (tdir / "redaction_report.md").write_text(
        "# Redaction Report\n\nNo secret values stored; request and decision files contain only references.\n"
    )
    (tdir / "report.md").write_text(
        "# Binding Secret Materialization\n\n"
        f"Timestamp (UTC): {stamp}\n"
        f"Tenant: {tenant}\n"
        f"Backend: {backend}\n"
        f"Mode: {'execute' if execute else 'dry-run'}\n\n"
        "Files:\n"
        "- request.json\n- decision.json\n- secret_refs.json\n- redaction_report.md\n"
    )
    print(tdir)
PY
)

while IFS= read -r dir; do
  [[ -z "${dir}" ]] && continue
  manifest_file="${dir}/manifest.sha256"
  (
    cd "${dir}"
    find . -type f ! -name "manifest.sha256" ! -name "manifest.sha256.asc" -print0 | sort -z | xargs -0 sha256sum
  ) > "${manifest_file}"

  if [[ "${EVIDENCE_SIGN:-0}" == "1" ]]; then
    bash "${FABRIC_REPO_ROOT}/ops/tenants/execute/signer.sh" "${manifest_file}"
  fi
  echo "PASS secrets materialize evidence -> ${dir}"
done <<< "${tenant_dirs}"

if [[ "${has_error}" == "1" ]]; then
  exit 2
fi
