#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


source "${FABRIC_REPO_ROOT}/ops/substrate/common/env.sh"
source "${FABRIC_REPO_ROOT}/ops/substrate/common/connectivity.sh"
source "${FABRIC_REPO_ROOT}/ops/substrate/common/evidence.sh"

collect_endpoints() {
  local tenant_dir="$1"
  local outfile="$2"
  local provider="$3"

  TENANT_DIR="${tenant_dir}" PROVIDER_FILTER="${provider}" python3 - <<'PY' >"${outfile}"
import json
import os
from pathlib import Path

tenant_dir = Path(os.environ["TENANT_DIR"])
provider_filter = os.environ.get("PROVIDER_FILTER") or None

entries = []
for enabled in sorted(tenant_dir.rglob("consumers/*/enabled.yml")):
    data = json.loads(enabled.read_text())
    consumer = data.get("consumer")
    if consumer not in {"database", "message-queue", "cache", "vector"}:
        continue
    provider = data.get("executor", {}).get("provider")
    if provider_filter and provider != provider_filter:
        continue
    variant = data.get("variant")
    endpoints = data.get("endpoints", {})
    entries.append(
        {
            "key": f"{consumer}:{provider}:{variant}",
            "consumer": consumer,
            "provider": provider,
            "variant": variant,
            "host": endpoints.get("host"),
            "port": endpoints.get("port"),
            "protocol": endpoints.get("protocol"),
            "tls_required": endpoints.get("tls_required"),
        }
    )

print(json.dumps(entries, indent=2, sort_keys=True))
PY
}

generate_plan() {
  local tenant_dir="$1"
  local tenant_id="$2"
  local out_dir="$3"
  local provider="$4"
  local stamp="$5"

  mkdir -p "${out_dir}"
  local endpoints_json="${out_dir}/.endpoints.json"
  local reachability_json="${out_dir}/.reachability.json"

  collect_endpoints "${tenant_dir}" "${endpoints_json}" "${provider}"
  connectivity_check "${endpoints_json}" "${reachability_json}" "${stamp}"

  TENANT_DIR="${tenant_dir}" PROVIDER_FILTER="${provider}" REACHABILITY_FILE="${reachability_json}" \
    TENANT_ID="${tenant_id}" OUT_DIR="${out_dir}" TIMESTAMP="${stamp}" \
    GIT_COMMIT="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)" python3 - <<'PY'
import json
import os
from pathlib import Path

provider_filter = os.environ.get("PROVIDER_FILTER") or None

tenant_dir = Path(os.environ["TENANT_DIR"])
out_dir = Path(os.environ["OUT_DIR"])
tenant_id = os.environ["TENANT_ID"]
stamp = os.environ["TIMESTAMP"]
git_commit = os.environ["GIT_COMMIT"]
reachability = json.loads(Path(os.environ["REACHABILITY_FILE"]).read_text())

plans = []
actions = []
endpoints_out = []

for enabled in sorted(tenant_dir.rglob("consumers/*/enabled.yml")):
    data = json.loads(enabled.read_text())
    consumer = data.get("consumer")
    if consumer not in {"database", "message-queue", "cache", "vector"}:
        continue
    provider = data.get("executor", {}).get("provider")
    if provider_filter and provider != provider_filter:
        continue
    variant = data.get("variant")
    executor = data.get("executor", {})
    endpoints = data.get("endpoints", {})
    key = f"{consumer}:{provider}:{variant}"
    reach = reachability.get(key, {"status": "unknown", "detail": "not_checked"})

    plan_entry = {
        "consumer": consumer,
        "provider": provider,
        "variant": variant,
        "executor": {
            "mode": executor.get("mode"),
            "plan_only": executor.get("plan_only"),
        },
        "endpoints": endpoints,
        "reachability": reach,
        "dr_testcases": data.get("dr", {}).get("required_testcases", []),
    }
    plans.append(plan_entry)
    actions.append(
        {
            "consumer": consumer,
            "provider": provider,
            "variant": variant,
            "actions": [
                "validate_contract",
                "evaluate_endpoints",
                "emit_plan_evidence",
            ],
        }
    )
    endpoints_out.append(
        {
            "consumer": consumer,
            "provider": provider,
            "variant": variant,
            "host": endpoints.get("host"),
            "port": endpoints.get("port"),
            "protocol": endpoints.get("protocol"),
            "tls_required": endpoints.get("tls_required"),
            "reachability": reach.get("status"),
        }
    )

plan = {
    "tenant_id": tenant_id,
    "timestamp_utc": stamp,
    "git_commit": git_commit,
    "plans": plans,
}

out_dir.mkdir(parents=True, exist_ok=True)
(out_dir / "plan.json").write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
(out_dir / "actions.json").write_text(json.dumps(actions, indent=2, sort_keys=True) + "\n")

lines = ["tenant_id: %s" % tenant_id, "endpoints:"]
for entry in endpoints_out:
    lines.append(f"  - consumer: {entry['consumer']}")
    lines.append(f"    provider: {entry['provider']}")
    lines.append(f"    variant: {entry['variant']}")
    lines.append(f"    host: {entry['host']}")
    lines.append(f"    port: {entry['port']}")
    lines.append(f"    protocol: {entry['protocol']}")
    lines.append(f"    tls_required: {entry['tls_required']}")
    lines.append(f"    reachability: {entry['reachability']}")

(out_dir / "endpoints.redacted.yml").write_text("\n".join(lines) + "\n")

(out_dir / "report.md").write_text(
    "# Substrate Plan Evidence\n\n"
    f"Tenant: {tenant_id}\n"
    f"Timestamp (UTC): {stamp}\n\n"
    "## Plan Summary\n"
    f"Plans generated: {len(plans)}\n"
)
PY

  local redacted_plan="${out_dir}/plan.redacted.json"
  "${FABRIC_REPO_ROOT}/ops/substrate/common/redaction.sh" "${out_dir}/plan.json" "${redacted_plan}"
  mv "${redacted_plan}" "${out_dir}/plan.json"
  rm -f "${endpoints_json}" "${reachability_json}"
}

generate_dr_dryrun() {
  local tenant_dir="$1"
  local tenant_id="$2"
  local out_dir="$3"
  local provider="$4"
  local stamp="$5"

  mkdir -p "${out_dir}"

  TENANT_DIR="${tenant_dir}" PROVIDER_FILTER="${provider}" TAXONOMY_FILE="${DR_TAXONOMY}" \
    TENANT_ID="${tenant_id}" OUT_DIR="${out_dir}" TIMESTAMP="${stamp}" \
    GIT_COMMIT="$(git -C "${FABRIC_REPO_ROOT}" rev-parse HEAD)" python3 - <<'PY'
import json
import os
from pathlib import Path

provider_filter = os.environ.get("PROVIDER_FILTER") or None

tenant_dir = Path(os.environ["TENANT_DIR"])
out_dir = Path(os.environ["OUT_DIR"])
tenant_id = os.environ["TENANT_ID"]
stamp = os.environ["TIMESTAMP"]
commit = os.environ["GIT_COMMIT"]

taxonomy = json.loads(Path(os.environ["TAXONOMY_FILE"]).read_text())
common_cases = set(taxonomy.get("common", []))
cluster_cases = set(taxonomy.get("cluster-only", []))

provider_map = {
    "database": {"postgres", "mariadb"},
    "message-queue": {"rabbitmq"},
    "cache": {"dragonfly"},
    "vector": {"qdrant"},
}

steps = []
used = []

for enabled in sorted(tenant_dir.rglob("consumers/*/enabled.yml")):
    data = json.loads(enabled.read_text())
    consumer = data.get("consumer")
    if consumer not in provider_map:
        continue
    provider = data.get("executor", {}).get("provider")
    if provider_filter and provider != provider_filter:
        continue
    if provider not in provider_map[consumer]:
        continue
    variant = data.get("variant")

    dr = data.get("dr", {})
    required = dr.get("required_testcases", [])
    backup = dr.get("backup", {})
    restore = dr.get("restore_verification", {})

    if not backup.get("schedule"):
        raise SystemExit(f"missing backup.schedule in {enabled}")
    if not backup.get("retention"):
        raise SystemExit(f"missing backup.retention in {enabled}")
    if not restore.get("smoke"):
        raise SystemExit(f"missing restore_verification.smoke in {enabled}")

    allowed = set(common_cases)
    section = taxonomy.get(consumer, {})
    if isinstance(section, dict):
        allowed.update(section.get(provider, []))
    if variant == "cluster":
        allowed.update(cluster_cases)

    for testcase in required:
        if testcase not in allowed:
            raise SystemExit(f"unknown testcase {testcase} in {enabled}")

    used.append(
        {
            "consumer": consumer,
            "provider": provider,
            "variant": variant,
            "required_testcases": required,
        }
    )

    steps.append(
        {
            "consumer": consumer,
            "provider": provider,
            "variant": variant,
            "steps": [
                "confirm backup target placeholders",
                "confirm restore verification placeholders",
                "emit DR dry-run evidence",
            ],
        }
    )

out_dir.mkdir(parents=True, exist_ok=True)
(out_dir / "testcases.json").write_text(json.dumps(used, indent=2, sort_keys=True) + "\n")
(out_dir / "steps.json").write_text(json.dumps(steps, indent=2, sort_keys=True) + "\n")

(out_dir / "report.md").write_text(
    "# Substrate DR Dry-Run Evidence\n\n"
    f"Tenant: {tenant_id}\n"
    f"Timestamp (UTC): {stamp}\n\n"
    "## DR Summary\n"
    f"Entries: {len(used)}\n"
)
PY

}
