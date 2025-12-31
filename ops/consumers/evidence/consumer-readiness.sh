#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"

mapfile -t contracts < <(find "${FABRIC_REPO_ROOT}/contracts/consumers" -mindepth 2 -maxdepth 2 -name "*.yml" -print | sort)

for contract in "${contracts[@]}"; do
  CONTRACT_PATH="$contract" OUT_DIR="${FABRIC_REPO_ROOT}/evidence/consumers" STAMP="$stamp" python3 - <<'PY'
import json
import os
from pathlib import Path

contract_path = Path(os.environ["CONTRACT_PATH"])

contract = json.loads(contract_path.read_text())
spec = contract["spec"]

consumer_type = spec["type"]
variant = spec["variant"]
name = contract["metadata"]["name"]

out_dir = Path(os.environ["OUT_DIR"]) / consumer_type / variant / os.environ["STAMP"]
out_dir.mkdir(parents=True, exist_ok=True)

report_path = out_dir / "report.md"
metadata_path = out_dir / "metadata.json"

report_lines = [
    f"# Consumer Readiness Report",
    "",
    f"- name: {name}",
    f"- type: {consumer_type}",
    f"- variant: {variant}",
    f"- timestamp: {os.environ['STAMP']}",
    "",
    "## HA readiness",
    f"- tier: {spec['ha']['tier']}",
    f"- replicas_min: {spec['ha']['replicas_min']}",
    f"- anti_affinity: {spec['ha']['anti_affinity']}",
    f"- failure_domains: {', '.join(spec['ha']['failure_domains'])}",
    "",
    "## Disaster coverage",
    f"- scenarios: {len(spec['disaster']['scenarios'])}",
    "",
    "## Observability intents",
    f"- metrics endpoints: {len(spec['observability']['metrics'])}",
    f"- log labels: {', '.join(spec['observability']['logs']['labels'])}",
    "",
    "## Firewall posture",
    f"- default_off: {spec['firewall']['default_off']}",
    f"- profile: {spec['firewall']['profile']}",
    "",
    "## Evidence references",
    "- substrate drift packet",
    "- consumer readiness packet",
]

if spec.get("evidence", {}).get("required_packets"):
    report_lines.append(f"- required packets: {', '.join(spec['evidence']['required_packets'])}")

if spec.get("secrets", {}).get("required"):
    report_lines.append("- secrets required (symbolic): " + ", ".join(spec["secrets"]["required"]))

gameday_root = Path(os.environ["FABRIC_REPO_ROOT"]) / "evidence" / "consumers" / "gameday" / name
latest_gameday = None
if gameday_root.exists():
    for testcase_dir in gameday_root.iterdir():
        if not testcase_dir.is_dir():
            continue
        for stamp_dir in testcase_dir.iterdir():
            if not stamp_dir.is_dir():
                continue
            if (stamp_dir / "report.md").exists():
                if latest_gameday is None or stamp_dir.name > latest_gameday.name:
                    latest_gameday = stamp_dir

if latest_gameday:
    report_lines.append(f"- latest gameday evidence: {latest_gameday}")

report_path.write_text("\n".join(report_lines) + "\n")

metadata = {
    "name": name,
    "type": consumer_type,
    "variant": variant,
    "timestamp_utc": os.environ["STAMP"],
    "contract_path": str(contract_path),
}
metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")

manifest_path = out_dir / "manifest.sha256"

import hashlib

def sha256_file(path):
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()

entries = [
    (report_path.name, sha256_file(report_path)),
    (metadata_path.name, sha256_file(metadata_path)),
]

manifest_lines = [f"{h}  {name}" for name, h in entries]
manifest_path.write_text("\n".join(manifest_lines) + "\n")

print(f"OK: evidence packet -> {out_dir}")
PY
done
