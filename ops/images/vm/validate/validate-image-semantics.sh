#!/usr/bin/env bash
set -euo pipefail

: "${FABRIC_REPO_ROOT:?FABRIC_REPO_ROOT must be set}"

# shellcheck disable=SC1091
source "${FABRIC_REPO_ROOT}/ops/runner/guard.sh"
require_ci_mode


python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

required_testcases = {
    "qcow2",
    "cloud-init",
    "ssh-posture",
    "pkg-manifest",
    "build-metadata",
}

contracts = [
    Path(os.environ["FABRIC_REPO_ROOT"]) / "contracts/images/vm/ubuntu-24.04/v1/image.yml",
    Path(os.environ["FABRIC_REPO_ROOT"]) / "contracts/images/vm/debian-12/v1/image.yml",
]

ok = True
for contract in contracts:
    data = json.loads(contract.read_text())
    spec = data.get("spec", {})

    cloud_init = spec.get("cloud_init", {})
    if cloud_init.get("enabled") is not True:
        print(f"{contract.name}: cloud_init.enabled must be true", file=sys.stderr)
        ok = False

    security = spec.get("security", {})
    if security.get("ssh_posture") != "key-only":
        print(f"{contract.name}: security.ssh_posture must be key-only", file=sys.stderr)
        ok = False

    artifact = spec.get("artifact", {})
    if artifact.get("format") != "qcow2":
        print(f"{contract.name}: artifact.format must be qcow2", file=sys.stderr)
        ok = False
    sha256 = artifact.get("sha256", "")
    if not sha256.startswith("sha256:"):
        print(f"{contract.name}: artifact.sha256 must start with sha256:", file=sys.stderr)
        ok = False

    build = spec.get("build", {})
    packer_path = build.get("packer_template_path", "")
    ansible_path = build.get("ansible_playbook_path", "")
    if not packer_path.startswith("images/packer/"):
        print(f"{contract.name}: build.packer_template_path must start with images/packer/", file=sys.stderr)
        ok = False
    if not ansible_path.startswith("images/ansible/"):
        print(f"{contract.name}: build.ansible_playbook_path must start with images/ansible/", file=sys.stderr)
        ok = False

    acceptance = spec.get("acceptance", {})
    testcases = set(acceptance.get("testcases", []))
    missing = required_testcases - testcases
    if missing:
        print(f"{contract.name}: acceptance.testcases missing {sorted(missing)}", file=sys.stderr)
        ok = False

if not ok:
    sys.exit(1)
PY
