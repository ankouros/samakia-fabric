#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


tenant_filter="${TENANT:-all}"
stamp="${ROTATION_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
base_dir="${FABRIC_REPO_ROOT}/evidence/bindings"

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

plan_path="${work_dir}/plan.json"
decision_path="${work_dir}/decision.json"

bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/rotate-plan.sh" --out "${plan_path}"

python3 - <<'PY' "${plan_path}" "${decision_path}"
import json
import sys
from pathlib import Path

plan_path = Path(sys.argv[1])
decision_path = Path(sys.argv[2])

plan = json.loads(plan_path.read_text())
entries = plan.get("entries", [])

results = []
for entry in entries:
    results.append({
        "tenant": entry.get("tenant"),
        "env": entry.get("env"),
        "secret_ref": entry.get("secret_ref"),
        "new_secret_ref": entry.get("new_secret_ref"),
        "secret_shape": entry.get("secret_shape"),
        "provider": entry.get("provider"),
        "status": "dry-run",
        "action": "plan",
        "reason": "dry-run",
    })

decision_path.write_text(json.dumps({"results": results}, indent=2, sort_keys=True) + "\n")
PY

tenant_dirs=$(python3 - <<'PY' "${plan_path}" "${decision_path}" "${base_dir}" "${stamp}" "${tenant_filter}"
import json
import sys
from pathlib import Path

plan_path = Path(sys.argv[1])
decision_path = Path(sys.argv[2])
base_dir = Path(sys.argv[3])
stamp = sys.argv[4]
flt = sys.argv[5]

plan = json.loads(plan_path.read_text())
results = json.loads(decision_path.read_text()).get("results", [])
entries = plan.get("entries", [])

if not entries:
    tenant_name = flt if flt != "all" else "all"
    tdir = base_dir / tenant_name / stamp / "rotation"
    tdir.mkdir(parents=True, exist_ok=True)
    (tdir / "plan.json").write_text(json.dumps({"rotation_stamp": plan.get("rotation_stamp"), "entries": []}, indent=2, sort_keys=True) + "\n")
    (tdir / "decision.json").write_text(json.dumps({"results": []}, indent=2, sort_keys=True) + "\n")
    (tdir / "secret_refs.json").write_text(json.dumps({"refs": []}, indent=2, sort_keys=True) + "\n")
    (tdir / "report.md").write_text(
        "# Binding Secret Rotation (Dry-run)\n\n"
        f"Timestamp (UTC): {stamp}\n"
        f"Tenant: {tenant_name}\n\nNo rotation entries found.\n"
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
        "# Binding Secret Rotation (Dry-run)\n\n"
        f"Timestamp (UTC): {stamp}\n"
        f"Tenant: {tenant}\n\nFiles:\n- plan.json\n- decision.json\n- secret_refs.json\n"
    )
    print(tdir)
PY
)

while IFS= read -r dir; do
  [[ -z "${dir}" ]] && continue
  bash "${FABRIC_REPO_ROOT}/ops/bindings/rotate/rotate-evidence.sh" "${dir}"
  echo "PASS rotate dry-run evidence -> ${dir}"
done <<< "${tenant_dirs}"
