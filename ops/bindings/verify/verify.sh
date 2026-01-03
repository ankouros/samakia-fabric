#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


mode="${VERIFY_MODE:-offline}"
backend="${BIND_SECRETS_BACKEND:-file}"
artifact_root="${BINDINGS_ARTIFACT_ROOT:-${FABRIC_REPO_ROOT}/artifacts/bindings}"

usage() {
  cat >&2 <<'EOT'
Usage:
  VERIFY_MODE=offline|live TENANT=<id|all> WORKLOAD=<id> verify.sh

Options:
  VERIFY_MODE=offline|live    Default: offline
  VERIFY_LIVE=1               Required for live mode
  TENANT=all|<id>             Default: all
  WORKLOAD=<id>               Optional; restrict within tenant
  BIND_SECRETS_BACKEND=file|vault
  BINDINGS_ARTIFACT_ROOT=<path>
EOT
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${mode}" != "offline" && "${mode}" != "live" ]]; then
  echo "ERROR: VERIFY_MODE must be offline or live" >&2
  exit 2
fi

if [[ "${mode}" == "live" ]]; then
  if [[ "${VERIFY_LIVE:-0}" != "1" ]]; then
    echo "ERROR: live mode requires VERIFY_LIVE=1" >&2
    exit 2
  fi
  if [[ "${CI:-0}" == "1" ]]; then
    echo "ERROR: live mode is not allowed in CI" >&2
    exit 2
  fi
fi

backend_script="${FABRIC_REPO_ROOT}/ops/bindings/secrets/backends/${backend}.sh"
if [[ ! -x "${backend_script}" ]]; then
  echo "ERROR: secrets backend not found or not executable: ${backend_script}" >&2
  exit 2
fi

bindings_root="${FABRIC_REPO_ROOT}/contracts/bindings/tenants"

if [[ "${TENANT:-all}" == "all" || -z "${TENANT:-}" ]]; then
  mapfile -t bindings < <(find "${bindings_root}" -type f -name "*.binding.yml" -print | sort)
else
  if [[ -n "${WORKLOAD:-}" ]]; then
    bindings=("${bindings_root}/${TENANT}/${WORKLOAD}.binding.yml")
  else
    mapfile -t bindings < <(find "${bindings_root}/${TENANT}" -type f -name "*.binding.yml" -print | sort)
  fi
fi

if [[ ${#bindings[@]} -eq 0 ]]; then
  echo "ERROR: no binding contracts found" >&2
  exit 1
fi

if [[ ! -d "${artifact_root}" ]]; then
  echo "ERROR: artifacts directory not found: ${artifact_root}" >&2
  echo "Run: make bindings.render TENANT=all" >&2
  exit 1
fi

run_id="$(date -u +%Y%m%dT%H%M%SZ)"
base_evidence="${FABRIC_REPO_ROOT}/evidence/bindings-verify"
mkdir -p "${base_evidence}"

TMP_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

tenant_lists_dir="${TMP_ROOT}/tenant-lists"
mkdir -p "${tenant_lists_dir}"
overall_status="PASS"

for binding_path in "${bindings[@]}"; do
  if [[ ! -f "${binding_path}" ]]; then
    echo "FAIL binding: missing ${binding_path}" >&2
    overall_status="FAIL"
    continue
  fi

  binding_tmp="${TMP_ROOT}/binding"
  mkdir -p "${binding_tmp}"

  python3 - "${binding_path}" "${artifact_root}" "${binding_tmp}" <<'PY'
import json
import os
import sys
from pathlib import Path
import yaml

binding_path = Path(sys.argv[1])
artifact_root = Path(sys.argv[2])
out_root = Path(sys.argv[3])

binding = yaml.safe_load(binding_path.read_text())
meta = binding.get("metadata", {})
consumers = binding.get("spec", {}).get("consumers", [])

tenant = meta.get("tenant")
workload_id = meta.get("workload_id")
workload_type = meta.get("workload_type")
env = meta.get("env")

if not tenant or not workload_id:
    raise SystemExit("ERROR: binding metadata missing tenant or workload_id")

conn_path = artifact_root / tenant / workload_id / "connection.json"
if not conn_path.exists():
    raise SystemExit(f"ERROR: connection manifest not found: {conn_path}")

try:
    conn = json.loads(conn_path.read_text())
except json.JSONDecodeError:
    conn = yaml.safe_load(conn_path.read_text())

conn_consumers = conn.get("consumers", [])
if len(conn_consumers) != len(consumers):
    raise SystemExit("ERROR: consumer count mismatch between binding and connection manifest")

entries_dir = out_root / "entries"
entries_dir.mkdir(parents=True, exist_ok=True)
entry_paths = []

for idx, (binding_consumer, conn_consumer) in enumerate(zip(consumers, conn_consumers), start=1):
    entry = {
        "tenant": tenant,
        "env": env,
        "workload_id": workload_id,
        "workload_type": workload_type,
        "binding_path": str(binding_path),
        "mode": os.environ.get("VERIFY_MODE", "offline"),
        "consumer": {
            "type": binding_consumer.get("type"),
            "provider": binding_consumer.get("provider"),
            "variant": binding_consumer.get("variant"),
            "access_mode": binding_consumer.get("access_mode"),
            "secret_ref": binding_consumer.get("secret_ref"),
            "secret_shape": binding_consumer.get("secret_shape"),
        },
        "endpoint": conn_consumer.get("endpoint", {}),
        "connection_profile": conn_consumer.get("connection_profile", {}),
        "resources": conn_consumer.get("resources", {}),
    }
    entry_path = entries_dir / f"consumer-{idx}.json"
    entry_path.write_text(json.dumps(entry, sort_keys=True, indent=2) + "\n")
    entry_paths.append(str(entry_path))

meta_out = {
    "tenant": tenant,
    "env": env,
    "workload_id": workload_id,
    "workload_type": workload_type,
    "binding_path": str(binding_path),
    "connection_manifest": str(conn_path),
}
(out_root / "meta.json").write_text(json.dumps(meta_out, sort_keys=True, indent=2) + "\n")
(out_root / "entries.list").write_text("\n".join(entry_paths) + "\n")
PY

  meta_file="${binding_tmp}/meta.json"
  entries_list="${binding_tmp}/entries.list"

  tenant_id="$(python3 - "${meta_file}" <<'PY'
import json
import sys
meta = json.loads(open(sys.argv[1]).read())
print(meta.get("tenant", ""))
PY
)"
  workload_id="$(python3 - "${meta_file}" <<'PY'
import json
import sys
meta = json.loads(open(sys.argv[1]).read())
print(meta.get("workload_id", ""))
PY
)"

  if [[ -z "${tenant_id}" || -z "${workload_id}" ]]; then
    echo "FAIL binding: invalid metadata for ${binding_path}" >&2
    overall_status="FAIL"
    continue
  fi

  out_dir="${base_evidence}/${tenant_id}/${run_id}"
  mkdir -p "${out_dir}/per-binding" "${out_dir}/tls"

  binding_results=()

  while IFS= read -r entry_file; do
    [[ -z "${entry_file}" ]] && continue

    consumer_type="$(python3 - "${entry_file}" <<'PY'
import json
import sys
entry = json.loads(open(sys.argv[1]).read())
print(entry.get("consumer", {}).get("type", ""))
PY
)"
    provider="$(python3 - "${entry_file}" <<'PY'
import json
import sys
entry = json.loads(open(sys.argv[1]).read())
print(entry.get("consumer", {}).get("provider", ""))
PY
)"
    secret_ref="$(python3 - "${entry_file}" <<'PY'
import json
import sys
entry = json.loads(open(sys.argv[1]).read())
print(entry.get("consumer", {}).get("secret_ref", ""))
PY
)"

    secret_file=""
    if [[ "${mode}" == "live" ]]; then
      if [[ -z "${secret_ref}" ]]; then
        echo "ERROR: secret_ref missing for ${binding_path}" >&2
        exit 1
      fi
      secret_file="${binding_tmp}/secret-${consumer_type}.json"
      if ! "${backend_script}" get "${secret_ref}" > "${secret_file}" 2>/dev/null; then
        echo "ERROR: failed to read secret_ref ${secret_ref} via backend ${backend}" >&2
        exit 1
      fi
    fi

    ca_file=""
    if [[ -n "${secret_file}" ]]; then
      ca_file="$(python3 - "${secret_file}" <<'PY'
import json
import sys
from pathlib import Path
secret = json.loads(open(sys.argv[1]).read())
ca_ref = secret.get("ca_ref") or secret.get("ca_path")
if not ca_ref:
    print("")
    sys.exit(0)
print(ca_ref)
PY
)"
      if [[ -n "${ca_file}" ]]; then
        if [[ ! -f "${ca_file}" ]]; then
          if [[ -f "${FABRIC_REPO_ROOT}/ops/ca/${ca_file}" ]]; then
            ca_file="${FABRIC_REPO_ROOT}/ops/ca/${ca_file}"
          elif [[ -f "${FABRIC_REPO_ROOT}/${ca_file}" ]]; then
            ca_file="${FABRIC_REPO_ROOT}/${ca_file}"
          fi
        fi
      fi
    fi

    tcp_file="${binding_tmp}/tcp_tls.json"
    bash "${FABRIC_REPO_ROOT}/ops/bindings/verify/probes/tcp_tls.sh" \
      --entry "${entry_file}" --mode "${mode}" --secret "${secret_file}" --ca-file "${ca_file}" > "${tcp_file}"

    probe_script=""
    case "${provider}" in
      postgres)
        probe_script="${FABRIC_REPO_ROOT}/ops/bindings/verify/probes/postgres.sh"
        ;;
      mariadb)
        probe_script="${FABRIC_REPO_ROOT}/ops/bindings/verify/probes/mariadb.sh"
        ;;
      rabbitmq)
        probe_script="${FABRIC_REPO_ROOT}/ops/bindings/verify/probes/rabbitmq.sh"
        ;;
      dragonfly)
        probe_script="${FABRIC_REPO_ROOT}/ops/bindings/verify/probes/dragonfly.sh"
        ;;
      qdrant)
        probe_script="${FABRIC_REPO_ROOT}/ops/bindings/verify/probes/qdrant.sh"
        ;;
      *)
        echo "ERROR: unsupported provider ${provider} for ${binding_path}" >&2
        exit 1
        ;;
    esac

    probe_file="${binding_tmp}/probe.json"
    bash "${probe_script}" --entry "${entry_file}" --mode "${mode}" --secret "${secret_file}" --ca-file "${ca_file}" > "${probe_file}"

    result_file="${binding_tmp}/result-${consumer_type}.json"
    python3 - "${entry_file}" "${tcp_file}" "${probe_file}" <<'PY' > "${result_file}"
import json
import sys
from pathlib import Path

def load(path):
    return json.loads(Path(path).read_text())

entry = load(sys.argv[1])
tcp = load(sys.argv[2])
probe = load(sys.argv[3])

status = "PASS"
for res in (tcp, probe):
    if res.get("status") == "FAIL":
        status = "FAIL"
        break
    if res.get("status") == "WARN" and status != "FAIL":
        status = "WARN"

result = {
    "tenant": entry.get("tenant"),
    "env": entry.get("env"),
    "workload_id": entry.get("workload_id"),
    "consumer": entry.get("consumer"),
    "endpoint": entry.get("endpoint"),
    "mode": entry.get("mode"),
    "status": status,
    "checks": {
        "tcp_tls": tcp,
        "provider": probe,
    },
}
print(json.dumps(result, sort_keys=True, indent=2))
PY

    cp "${result_file}" "${out_dir}/per-binding/${workload_id}-${consumer_type}.json"
    cp "${tcp_file}" "${out_dir}/tls/${workload_id}-${consumer_type}.json"
    binding_results+=("${result_file}")
  done < "${entries_list}"

  binding_summary_file="${binding_tmp}/binding-summary.json"
  python3 - "${meta_file}" "${binding_summary_file}" "${binding_results[@]}" <<'PY'
import json
import sys
from pathlib import Path

meta = json.loads(Path(sys.argv[1]).read_text())
result_paths = sys.argv[3:]

results = []
status = "PASS"
for path in result_paths:
    data = json.loads(Path(path).read_text())
    results.append(data)
    if data.get("status") == "FAIL":
        status = "FAIL"
    elif data.get("status") == "WARN" and status != "FAIL":
        status = "WARN"

summary = {
    "tenant": meta.get("tenant"),
    "env": meta.get("env"),
    "workload_id": meta.get("workload_id"),
    "workload_type": meta.get("workload_type"),
    "status": status,
    "results": results,
}
Path(sys.argv[2]).write_text(json.dumps(summary, sort_keys=True, indent=2) + "\n")
PY

  cp "${binding_summary_file}" "${out_dir}/per-binding/${workload_id}.json"
  binding_status="$(python3 - "${binding_summary_file}" <<'PY'
import json
import sys
summary = json.loads(open(sys.argv[1]).read())
print(summary.get("status"))
PY
)"

  printf '%s %s\n' "${binding_status}" "${workload_id}" >> "${tenant_lists_dir}/${tenant_id}.summary"
  printf '%s\n' "${out_dir}/per-binding/${workload_id}.json" >> "${tenant_lists_dir}/${tenant_id}.jsonlist"
  if [[ "${binding_status}" == "FAIL" ]]; then
    overall_status="FAIL"
  elif [[ "${binding_status}" == "WARN" && "${overall_status}" != "FAIL" ]]; then
    overall_status="WARN"
  fi

done

for summary_file in "${tenant_lists_dir}"/*.summary; do
  [[ -e "${summary_file}" ]] || continue
  tenant_id="$(basename "${summary_file}" .summary)"
  tenant_dir="${base_evidence}/${tenant_id}/${run_id}"
  report_file="${tenant_dir}/report.md"
  results_json="${tenant_dir}/results.json"
  json_list="${tenant_lists_dir}/${tenant_id}.jsonlist"

  report_file="${tenant_dir}/summary.md"
  {
    echo "# Bindings verify summary"
    echo
    echo "Tenant: ${tenant_id}"
    echo "Mode: ${mode}"
    echo "Run ID: ${run_id}"
    echo
    echo "Results:"
    while IFS= read -r line; do
      echo "- ${line}"
    done < "${summary_file}"
  } > "${report_file}"

  python3 - "${json_list}" <<'PY' > "${results_json}"
import json
import sys
from pathlib import Path

list_path = Path(sys.argv[1])
entries = []
for line in list_path.read_text().splitlines():
    if not line:
        continue
    path = Path(line)
    entries.append(json.loads(path.read_text()))
print(json.dumps(entries, sort_keys=True, indent=2))
PY

  tls_endpoints="${tenant_dir}/tls/endpoints.json"
  python3 - "${tenant_dir}/tls" <<'PY' > "${tls_endpoints}"
import json
import sys
from pathlib import Path

tls_dir = Path(sys.argv[1])
entries = []
for path in sorted(tls_dir.glob("*.json")):
    if path.name == "endpoints.json":
        continue
    entries.append(json.loads(path.read_text()))
print(json.dumps(entries, sort_keys=True, indent=2))
PY

  manifest="${tenant_dir}/manifest.sha256"
  {
    echo "$(sha256sum "${report_file}" | awk '{print $1}')  $(basename "${report_file}")"
    echo "$(sha256sum "${results_json}" | awk '{print $1}')  $(basename "${results_json}")"
    echo "$(sha256sum "${tls_endpoints}" | awk '{print $1}')  $(basename "${tls_endpoints}")"
  } > "${manifest}"
done

if [[ "${overall_status}" == "FAIL" ]]; then
  echo "FAIL bindings verify" >&2
  exit 1
fi

if [[ "${overall_status}" == "WARN" ]]; then
  echo "WARN bindings verify (mode=${mode})" >&2
  exit 0
fi

echo "PASS bindings verify (mode=${mode})"
