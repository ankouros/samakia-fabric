#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


usage() {
  cat >&2 <<'EOT'
Usage:
  rotate.sh TENANT=<id|all>

Environment:
  ROTATE_EXECUTE=1                 (required to write secrets)
  ROTATE_REASON="<text>"           (required)
  BIND_SECRETS_BACKEND=file        (writes only supported for file backend)
  ROTATE_INPUT_FILE=<path>         (JSON map of secret_ref/new_secret_ref -> object)
  BIND_SECRET_INPUT_FILE=<path>    (fallback input map if ROTATE_INPUT_FILE unset)
  SECRETS_GENERATE=1               (allow generation when no input map provided)
  SECRETS_GENERATE_ALLOWLIST=tenant1,tenant2
  EVIDENCE_SIGN=1 EVIDENCE_SIGN_KEY=<id> (required for prod)
  MAINT_WINDOW_START/MAINT_WINDOW_END (required for prod)
EOT
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${ROTATE_EXECUTE:-0}" != "1" ]]; then
  echo "ERROR: set ROTATE_EXECUTE=1 to perform rotation writes" >&2
  exit 2
fi

if [[ "${CI:-0}" == "1" ]]; then
  echo "ERROR: secret rotation execute is not allowed in CI" >&2
  exit 2
fi

if [[ -z "${ROTATE_REASON:-}" ]]; then
  echo "ERROR: ROTATE_REASON is required for rotation" >&2
  exit 2
fi

backend="${BIND_SECRETS_BACKEND:-file}"
backend_script="${FABRIC_REPO_ROOT}/ops/bindings/secrets/backends/${backend}.sh"
file_backend="${FABRIC_REPO_ROOT}/ops/bindings/secrets/backends/file.sh"

tenant_filter="${TENANT:-all}"
stamp="${ROTATION_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
base_dir="${FABRIC_REPO_ROOT}/evidence/bindings"

if [[ "${backend}" != "file" ]]; then
  echo "ERROR: rotation writes only supported with BIND_SECRETS_BACKEND=file" >&2
  exit 2
fi
if [[ ! -x "${backend_script}" ]]; then
  echo "ERROR: secrets backend not found or not executable: ${backend_script}" >&2
  exit 2
fi
if [[ ! -x "${file_backend}" ]]; then
  echo "ERROR: file backend not found or not executable: ${file_backend}" >&2
  exit 2
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

plan_path="${work_dir}/plan.json"
results_path="${work_dir}/results.tsv"

TENANT="${tenant_filter}" ROTATION_STAMP="${stamp}" \
  bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/rotate-plan.sh" --out "${plan_path}"

entries_tsv=$(python3 - <<'PY' "${plan_path}"
import json
import sys
from pathlib import Path

plan_path = Path(sys.argv[1])
plan = json.loads(plan_path.read_text())
for entry in plan.get("entries", []):
    print("\t".join([
        str(entry.get("tenant") or ""),
        str(entry.get("env") or ""),
        str(entry.get("secret_ref") or ""),
        str(entry.get("new_secret_ref") or ""),
        str(entry.get("secret_shape") or ""),
        str(entry.get("provider") or ""),
    ]))
PY
)

if [[ -z "${entries_tsv}" ]]; then
  tenant_name="${tenant_filter}"
  if [[ "${tenant_name}" == "all" ]]; then
    tenant_name="all"
  fi
  empty_dir="${base_dir}/${tenant_name}/${stamp}/rotation"
  mkdir -p "${empty_dir}"
  printf '{"rotation_stamp":"%s","entries":[]}' "${stamp}" >"${empty_dir}/plan.json"
  printf '{"results":[]}' >"${empty_dir}/decision.json"
  printf '{"refs":[]}' >"${empty_dir}/secret_refs.json"
  cat >"${empty_dir}/report.md" <<REPORT_EOF
# Binding Secret Rotation (Execute)

Timestamp (UTC): ${stamp}
Tenant: ${tenant_name}

No rotation entries found. Nothing to do.
REPORT_EOF
  bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/rotate-evidence.sh" "${empty_dir}"
  exit 0
fi

if grep -q $'\tprod\t' <<<"${entries_tsv}"; then
  if [[ "${EVIDENCE_SIGN:-0}" != "1" || -z "${EVIDENCE_SIGN_KEY:-}" ]]; then
    echo "ERROR: prod rotation requires EVIDENCE_SIGN=1 and EVIDENCE_SIGN_KEY" >&2
    exit 2
  fi
  if ! bash "${FABRIC_REPO_ROOT}/ops/tenants/execute/change-window.sh"; then
    echo "ERROR: prod rotation requires a valid change window" >&2
    exit 2
  fi
fi

input_file="${ROTATE_INPUT_FILE:-${BIND_SECRET_INPUT_FILE:-}}"
if [[ -n "${input_file}" && ! -f "${input_file}" ]]; then
  echo "ERROR: input file not found: ${input_file}" >&2
  exit 2
fi

has_error="0"
while IFS=$'\t' read -r tenant env secret_ref new_secret_ref secret_shape provider; do
  status="ok"
  action="rotate"
  reason="executed"

  if [[ -z "${secret_ref}" || -z "${new_secret_ref}" || -z "${secret_shape}" ]]; then
    status="error"
    reason="missing_fields"
  fi

  tmp_file=""
  if [[ "${status}" == "ok" ]]; then
    if [[ -n "${input_file}" ]]; then
      tmp_file="$(mktemp)"
      if ! python3 - "${input_file}" "${new_secret_ref}" "${secret_ref}" >"${tmp_file}" <<'PY'
import json
import sys
from pathlib import Path

src = Path(sys.argv[1])
new_ref = sys.argv[2]
old_ref = sys.argv[3]

payloads = json.loads(src.read_text())
if new_ref in payloads:
    payload = payloads[new_ref]
elif old_ref in payloads:
    payload = payloads[old_ref]
else:
    raise SystemExit("ERROR: input map missing entry for secret_ref")

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
    elif [[ "${SECRETS_GENERATE:-0}" == "1" ]]; then
      if [[ -z "${SECRETS_GENERATE_ALLOWLIST:-}" ]] || ! grep -q "\b${tenant}\b" <<<"${SECRETS_GENERATE_ALLOWLIST//,/ }"; then
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
    else
      status="error"
      reason="input_missing"
    fi
  fi

  if [[ "${status}" == "ok" && -n "${tmp_file}" ]]; then
    if bash "${file_backend}" put "${new_secret_ref}" "${tmp_file}"; then
      reason="executed"
    else
      status="error"
      reason="backend_write_failed"
    fi
    rm -f "${tmp_file}"
  fi

  if [[ "${status}" == "error" ]]; then
    has_error="1"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${tenant}" "${env}" "${secret_ref}" "${new_secret_ref}" "${secret_shape}" "${provider}" "${status}" "${action}" "${reason}" \
    >>"${results_path}"

done <<< "${entries_tsv}"

tenant_dirs=$(python3 - <<'PY' "${plan_path}" "${results_path}" "${base_dir}" "${stamp}" "${tenant_filter}" "${ROTATE_REASON}"
import json
import sys
from pathlib import Path

plan_path = Path(sys.argv[1])
results_path = Path(sys.argv[2])
base_dir = Path(sys.argv[3])
stamp = sys.argv[4]
flt = sys.argv[5]
reason = sys.argv[6]

plan = json.loads(plan_path.read_text())
entries = plan.get("entries", [])
results = []
for line in results_path.read_text().splitlines():
    tenant, env, secret_ref, new_ref, shape, provider, status, action, reason_code = line.split("\t")
    results.append({
        "tenant": tenant,
        "env": env,
        "secret_ref": secret_ref,
        "new_secret_ref": new_ref,
        "secret_shape": shape,
        "provider": provider,
        "status": status,
        "action": action,
        "reason": reason_code,
    })

if not entries:
    tenant_name = flt if flt != "all" else "all"
    tdir = base_dir / tenant_name / stamp / "rotation"
    tdir.mkdir(parents=True, exist_ok=True)
    (tdir / "plan.json").write_text(json.dumps({"rotation_stamp": plan.get("rotation_stamp"), "entries": []}, indent=2, sort_keys=True) + "\n")
    (tdir / "decision.json").write_text(json.dumps({"results": []}, indent=2, sort_keys=True) + "\n")
    (tdir / "secret_refs.json").write_text(json.dumps({"refs": []}, indent=2, sort_keys=True) + "\n")
    (tdir / "report.md").write_text(
        "# Binding Secret Rotation (Execute)\n\n"
        f"Timestamp (UTC): {stamp}\nTenant: {tenant_name}\nReason: {reason}\n\nNo rotation entries found.\n"
    )
    print(tdir)
    sys.exit(0)

by_tenant = {}
for entry in entries:
    by_tenant.setdefault(entry.get("tenant"), {"entries": [], "results": []})
    by_tenant[entry.get("tenant")]["entries"].append(entry)
for result in results:
    by_tenant.setdefault(result.get("tenant"), {"entries": [], "results": []})
    by_tenant[result.get("tenant")]["results"].append(result)

for tenant in sorted(by_tenant.keys()):
    tdir = base_dir / tenant / stamp / "rotation"
    tdir.mkdir(parents=True, exist_ok=True)
    plan_payload = {
        "rotation_stamp": plan.get("rotation_stamp"),
        "entries": by_tenant[tenant]["entries"],
    }
    refs = {
        "refs": [
            {
                "tenant": e.get("tenant"),
                "env": e.get("env"),
                "secret_ref": e.get("secret_ref"),
                "new_secret_ref": e.get("new_secret_ref"),
                "secret_shape": e.get("secret_shape"),
            }
            for e in by_tenant[tenant]["entries"]
        ]
    }
    (tdir / "plan.json").write_text(json.dumps(plan_payload, indent=2, sort_keys=True) + "\n")
    (tdir / "decision.json").write_text(json.dumps({"results": by_tenant[tenant]["results"]}, indent=2, sort_keys=True) + "\n")
    (tdir / "secret_refs.json").write_text(json.dumps(refs, indent=2, sort_keys=True) + "\n")
    (tdir / "report.md").write_text(
        "# Binding Secret Rotation (Execute)\n\n"
        f"Timestamp (UTC): {stamp}\nTenant: {tenant}\nReason: {reason}\n\n"
        "Files:\n- plan.json\n- decision.json\n- secret_refs.json\n"
    )
    print(tdir)
PY
)

while IFS= read -r dir; do
  [[ -z "${dir}" ]] && continue
  bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/rotate-evidence.sh" "${dir}"
  echo "PASS rotate evidence -> ${dir}"
done <<< "${tenant_dirs}"

if [[ "${has_error}" == "1" ]]; then
  exit 2
fi
