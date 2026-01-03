# REQUIRED-FIXES — MinIO Backend Automation Remediation Status

This document records what was fixed, what remains blocked (if anything), and the exact verification status for the MinIO backend automation in **Samakia Fabric**.

---

## Phase 1 Remediation Status (from verification report)

### PHASE1-TF-NONINTERACTIVE
- **Description:** `CI=1 make tf.plan ENV=samakia-prod` failed due to interactive backend migration prompt.
- **Impact:** Violates Phase 1 requirement for non-interactive Terraform defaults.
- **Root cause:** Remote backend state for `samakia-prod` required migration; `terraform init -input=false` cannot prompt.
- **Required remediation:** Migrate state to MinIO backend non-interactively.
- **Resolution status:** **FIXED**
- **Evidence:**
  - `bash ops/scripts/tf-backend-init.sh samakia-prod --migrate` (completed)
  - `CI=1 make tf.plan ENV=samakia-prod` (PASS)
  - `ENV=samakia-prod make phase1.accept` (PASS)

### PHASE1-INVENTORY-SANITY
- **Description:** `make inventory.check` failed for `monitoring-1` (IPv4 not resolvable via Proxmox API).
- **Impact:** Violates Phase 1 requirement for DHCP/MAC determinism + inventory sanity.
- **Root cause:** `monitoring-1` container was deleted outside Terraform and template `v3` was missing in Proxmox storage.
- **Required remediation:** Upload missing template and recreate `monitoring-1` via Terraform apply.
- **Resolution status:** **FIXED**
- **Evidence:**
  - `make image.upload IMAGE=fabric-core/packer/lxc/ubuntu-24.04/ubuntu-24.04-lxc-rootfs-v3.tar.gz` (uploaded `v3` template)
  - `CI=1 make tf.apply ENV=samakia-prod` (recreated CT 1100)
  - `make inventory.check ENV=samakia-prod` (PASS with warning)
  - `ENV=samakia-prod make phase1.accept` (PASS)

---

## Phase 14 Part 3 Remediation Status

### PHASE14-PART3-INCIDENT-ENV
- **Description:** `make phase14.part3.accept` failed at the incident open step with `command not found`.
- **Impact:** Phase 14 Part 3 acceptance could not complete; acceptance marker not generated.
- **Root cause:** `ops/scripts/phase14-part3-accept.sh` passed env assignments directly into `run_step`, which executes `"$@"`; the env assignments were treated as the command.
- **Required remediation:** Prefix the incident open/close steps with `env` so assignments apply to `make`.
- **Resolution status:** **FIXED**
- **Verification command(s):**
  - `make phase14.part3.accept` (PASS)

---

## Fixed

- **Proxmox SDN planes are applied after creation (required for immediate use)**
  - Files affected:
    - `ops/scripts/proxmox-sdn-ensure-stateful-plane.sh` (now applies SDN via `PUT /cluster/sdn` when changed, and supports `--apply`/`--check-only`)
    - `ops/scripts/proxmox-sdn-ensure-dns-plane.sh` (same behavior for DNS SDN plane)
    - `Makefile:~921` (`make minio.up` runs stateful SDN apply early)
  - Reason: Proxmox SDN primitives are not usable until SDN config is applied cluster-wide.
  - Risk level: **low**
  - Behavior change: SDN ensure now includes an explicit apply step when needed (or forced).

- **Aligned edge management IP contracts repo-wide (no collisions with VIPs)**
  - Files affected:
    - `fabric-core/terraform/envs/samakia-minio/main.tf:114` and `fabric-core/terraform/envs/samakia-minio/main.tf:164` (`minio-edge-1/2` LAN mgmt IPs → `192.168.11.102/103`)
    - `fabric-core/terraform/envs/samakia-dns/main.tf:103` and `fabric-core/terraform/envs/samakia-dns/main.tf:153` (`dns-edge-1/2` LAN mgmt IPs → `192.168.11.111/112`)
    - `fabric-core/ansible/host_vars/minio-edge-1.yml:1` and `fabric-core/ansible/host_vars/minio-edge-2.yml:1`
    - `fabric-core/ansible/host_vars/dns-edge-1.yml:1` and `fabric-core/ansible/host_vars/dns-edge-2.yml:1`
    - `fabric-core/ansible/host_vars/minio-1.yml:5`, `fabric-core/ansible/host_vars/minio-2.yml:5`, `fabric-core/ansible/host_vars/minio-3.yml:5` (ProxyJump updated to `192.168.11.102,192.168.11.103`)
    - `fabric-core/ansible/host_vars/dns-auth-1.yml:6` and `fabric-core/ansible/host_vars/dns-auth-2.yml:6` (ProxyJump updated to `192.168.11.111,192.168.11.112`)
    - `ops/scripts/minio-accept.sh:12` and `ops/scripts/dns-accept.sh:11` (acceptance scripts updated to match canonical edge mgmt IPs)
    - `fabric-core/ansible/roles/dns_edge_gateway/templates/nftables.conf.j2:19` and `fabric-core/ansible/roles/dns_edge_gateway/templates/keepalived.conf.j2:17` (dns-edge VRRP peer allowlist + unicast peer mapping updated)
  - Reason: The repo previously had a collision/mismatch (`dns-edge-*` using `192.168.11.102/103` and `minio-edge-*` using `192.168.11.111/112`) which violates the canonical “VIP-only endpoints + non-colliding management IPs” contract.
  - Risk level: **medium** (network addressing changes can require CT recreate; correctness-preserving but operationally impactful).
  - Behavior change: Terraform plans will now converge to:
    - `minio-edge-1/2` LAN mgmt: `192.168.11.102/103`
    - `dns-edge-1/2` LAN mgmt: `192.168.11.111/112`

- **Fixed Proxmox SDN subnet API contract (Proxmox 9)**
  - Files affected:
    - `ops/scripts/proxmox-sdn-ensure-stateful-plane.sh` (VLAN140 `zminio/vminio`)
    - `ops/scripts/proxmox-sdn-ensure-dns-plane.sh` (VLAN100 `zonedns/vlandns`)
  - Reason: Proxmox 9 SDN subnet creation requires `type=subnet`, and the subnet list uses `cidr` (not `subnet`) for `10.10.x.0/24` matching; the ensure scripts must be deterministic and idempotent.
  - Risk level: **low**
  - Behavior change: SDN ensure now works on a clean Proxmox 9 SDN API and can correctly detect existing subnets.

- **Hardened SDN ensure failure reporting (secrets-safe, no stack traces)**
  - Files affected:
    - `ops/scripts/proxmox-sdn-ensure-stateful-plane.sh:~200+` (Python exception handling)
  - Reason: The prior failure mode surfaced Python tracebacks and did not clearly state the required Proxmox privilege.
  - Risk level: **low**
  - Behavior change: On `HTTP 403` with `SDN.Allocate`, the script now fails with a concise, actionable error message and required SDN plane contract.

- **Documentation aligned to the canonical IP/VIP policy**
  - Files affected:
    - `OPERATIONS.md:~85+` (explicit VIP vs mgmt IP policy + collision rule + SDN privilege note)
    - `DECISIONS.md:~324+` (ADR-0013 adds dns-edge mgmt IPs; ADR-0014 adds minio-edge mgmt IPs + SDN privilege note)
    - `REVIEW.md:10` and `REVIEW.md:118` (topology IPs updated; records current `make minio.up` failure cause)
    - `CHANGELOG.md:84` (Unreleased entry updated to reflect current mgmt IP alignment)
  - Reason: Docs must be consistent with enforced contracts and acceptance scripts.
  - Risk level: **low**
  - Behavior change: Documentation only.

## Still Blocked (if any)

- Milestone Phase 1–12 verification (see MILESTONE-1-12-PHASE2-1-SHARED-POLICY).
- Phase 17 Step 4 real canary exposure (see PHASE17-STEP4-CANARY-VERIFY-SECRET).

## Phase 17 Step 4 Blockers

### PHASE17-STEP4-CANARY-VERIFY-SECRET
- **Description:** `VERIFY_LIVE=1 make exposure.verify ENV=samakia-dev TENANT=canary WORKLOAD=sample` failed with `failed to read secret_ref tenants/canary/database/sample via backend file`.
- **Impact:** Phase 17 Step 4 cannot complete because live verification requires real secret material to validate TLS connectivity.
- **Root cause:** Local secrets backend file (`~/.config/samakia-fabric/secrets.enc`) is missing or unseeded for the canary `secret_ref`.
- **Required remediation:** Seed the file backend with the `tenants/canary/database/sample` secret (or configure the Vault backend) and rerun the verify step; ensure `SECRETS_PASSPHRASE` or `SECRETS_PASSPHRASE_FILE` is set for the runner.
- **Resolution status:** **OPEN**
- **Verification command(s):**
  - `VERIFY_LIVE=1 make exposure.verify ENV=samakia-dev TENANT=canary WORKLOAD=sample`

## Milestone Phase 1–12 Blockers

### MILESTONE-1-12-PHASE2-DNS
- **Description:** `make milestone.phase1-12.verify` falsely failed at Section D even though `ENV=samakia-dns make phase2.accept` passes.
- **Impact:** Milestone Phase 1–12 verification cannot be completed; milestone acceptance marker cannot be issued.
- **Root cause:** Wrapper exit semantics and missing per-step stdout/stderr capture in the milestone verifier; Phase 2 DNS itself was not failing.
- **Required remediation:** Fix milestone wrapper to preserve stdout/stderr per step, propagate real exit codes, and rerun `make milestone.phase1-12.verify`.
- **Resolution status:** **FIXED**
- **Verification command(s):**
  - `bash ops/scripts/test-milestone/test-wrapper-exit-semantics.sh` (PASS)
  - `make milestone.phase1-12.verify` (blocked by MILESTONE-1-12-MINIO-BACKEND-SMOKE)

### MILESTONE-1-12-MINIO-BACKEND-SMOKE
- **Description:** `make milestone.phase1-12.verify` failed in Section D during `ENV=samakia-minio make phase2.accept` because `minio.backend.smoke` reported “backend type not confirmed in init output”.
- **Impact:** Milestone Phase 1–12 verification could not be completed; milestone acceptance marker could not be issued.
- **Root cause:** `TF_CLI_ARGS_init` in the milestone verifier forced `-backend=false`, suppressing the backend marker in `terraform init` output and tripping the smoke parser.
- **Required remediation:** Remove the forced `-backend=false` default for milestone verification and rerun the milestone suite.
- **Resolution status:** **FIXED**
- **Evidence:**
  - `audit/minio-backend-smoke/20260102T130656Z/report.md`
  - `audit/minio-backend-smoke/20260102T130656Z/terraform-init.txt`
- **Verification command(s):**
  - `make milestone.phase1-12.verify` (blocked by MILESTONE-1-12-PHASE2-1-SHARED-POLICY)

### MILESTONE-1-12-PHASE2-1-SHARED-POLICY
- **Description:** `make milestone.phase1-12.verify` fails in Section D during `ENV=samakia-shared make phase2.1.accept` at the shared observability policy gate.
- **Impact:** Milestone Phase 1–12 verification cannot be completed; milestone acceptance marker cannot be issued.
- **Root cause:** The shared observability tier does not currently satisfy policy requirements (anti-affinity, replica count, and host count).
- **Required remediation:** Bring shared observability workloads into compliance (anti_affinity=true, replicas>=2, at least 2 hosts) and rerun milestone verification.
- **Resolution status:** **FIXED**
- **Evidence:**
  - `evidence/milestones/phase1-12/2026-01-02T13:14:52Z/steps/phase2-1-shared/stderr.log`
  - `ENV=samakia-shared make phase2.1.accept` (PASS)
- **Verification command(s):**
  - `ENV=samakia-shared make phase2.1.accept`
  - `make milestone.phase1-12.verify`

### MILESTONE-1-12-PHASE2-MINIO-TIME-SKEW
- **Description:** `make milestone.phase1-12.verify` failed in Section D during `ENV=samakia-dns make phase2.accept` because MinIO convergence reported time skew > 1s.
- **Impact:** Milestone Phase 1–12 verification cannot be completed; milestone acceptance marker cannot be issued.
- **Root cause:** MinIO nodes lacked chrony client setup, and the skew check was serialized enough to exceed the 1s threshold under normal SSH latency.
- **Required remediation:** Install chrony client on MinIO nodes and collect time samples concurrently, then re-run MinIO convergence acceptance.
- **Resolution status:** **FIXED**
- **Verification command(s):**
  - `ENV=samakia-minio ANSIBLE_FLAGS="--limit minio-1,minio-2,minio-3" make minio.ansible.apply`
  - `ENV=samakia-minio make minio.converged.accept`

### MILESTONE-1-12-PHASE3-PART3-GPG
- **Description:** `make milestone.phase1-12.verify` failed in Section E during `ENV=samakia-prod make phase3.part3.accept` because the Phase 12 readiness packet test attempted GPG signing without a configured default secret key.
- **Impact:** Milestone Phase 1–12 verification cannot be completed; milestone acceptance marker cannot be issued.
- **Root cause:** The milestone wrapper test inherits `ENV=samakia-prod`, which enables manifest signing inside `verify.sh` even in test mode, and no default GPG key was configured on the runner.
- **Required remediation:** Disable milestone manifest signing when `MILESTONE_TEST_MODE=1`, then re-run the wrapper exit semantics test.
- **Resolution status:** **FIXED**
- **Verification command(s):**
  - `bash ops/scripts/test-milestone/test-wrapper-exit-semantics.sh`

## Verification Status

Commands executed (local):

- `make help`: **PASS**
- `make minio.up ENV=samakia-minio`: **PASS**
- `make minio.accept`: **PASS**
- `make minio.quorum.guard ENV=samakia-minio`: **PASS**
- `make minio.backend.smoke ENV=samakia-minio`: **PASS**
- `make minio.state.migrate ENV=samakia-minio`: **PASS**

Final status:
- `make minio.up ENV=samakia-minio`: **PASS**

---

## Phase 2.1 Blockers

### PHASE2_1-SDN-ACCEPT-NFT
- **Description:** `ENV=samakia-shared make phase2.1.accept` failed in `shared.sdn.accept` during nftables/NAT validation on the active shared edge.
- **Impact:** Phase 2.1 acceptance cannot proceed; shared plane not locked.
- **Root cause:** `ops/scripts/shared-sdn-accept.sh` executed nftables checks on the edge without sufficient privileges. The remote command returned `Operation not permitted (you must be root)` and the script failed the NAT masquerade check.
- **Required remediation:** Update `ops/scripts/shared-sdn-accept.sh` to run nftables inspection with `sudo -n`, and fail loudly if sudo is not permitted.
- **Resolution status:** **FIXED**
- **Verification command(s):**
  - `ENV=samakia-shared make shared.sdn.accept` (PASS)
  - `ENV=samakia-shared make phase2.1.accept` (progressed past shared.sdn.accept)

### PHASE2_1-OBS-GRAFANA
- **Description:** `ENV=samakia-shared make phase2.1.accept` failed in `shared.obs.accept` with Grafana returning HTTP 503 on VIP `https://192.168.11.122:3000/`.
- **Impact:** Phase 2.1 acceptance cannot complete; shared observability plane not validated.
- **Root cause:** Grafana admin password file was not created on the controller; Prometheus failed to start due to systemd sandboxing in unprivileged LXC.
- **Required remediation:** Fix Grafana password file creation and apply an LXC-safe Prometheus systemd override, then re-run shared observability apply.
- **Resolution status:** **FIXED**
- **Verification command(s):**
  - `ENV=samakia-shared make shared.obs.accept` (PASS)
  - `ENV=samakia-shared make phase2.1.accept` (PASS)

### PHASE2_1-OBS-LOKI-READY
- **Description:** `ENV=samakia-shared make phase2.1.accept` failed in `shared.obs.accept` with Loki `/ready` returning HTTP 503 on the shared VIP.
- **Impact:** Phase 2.1 acceptance could not complete; shared observability plane not validated.
- **Root cause:** Loki was upgraded with a v11 schema but structured metadata defaults required v13 + `tsdb` index, and `/var/lib/loki` lacked writable ownership for the Loki service user.
- **Required remediation:** Disable structured metadata in Loki config and ensure `/var/lib/loki` directories are owned by the Loki user/group, then re-run shared observability apply.
- **Resolution status:** **FIXED**
- **Verification command(s):**
  - `ENV=samakia-shared ANSIBLE_FLAGS="--limit obs-1,obs-2" make shared.ansible.apply`
  - `ENV=samakia-shared make shared.obs.accept`

---

## Phase 11 Part 3 Blockers

### PHASE11-PART3-MISSING-PART2-MARKER
- **Description:** Phase 11 Part 3 hard gate failed because `acceptance/PHASE11_PART2_ACCEPTED.md` is missing.
- **Impact:** Phase 11 Part 3 implementation cannot start; hard gate requires Part 2 acceptance.
- **Root cause:** Phase 11 Part 2 has not been accepted/locked in this repo state.
- **Required remediation:** Complete Phase 11 Part 2 acceptance and create `acceptance/PHASE11_PART2_ACCEPTED.md` (with self-hash) per the Phase 11 Part 2 protocol.
- **Resolution status:** **FIXED**
- **Verification command(s):**
  - `make phase11.part2.accept` (PASS)
  - `test -f acceptance/PHASE11_PART2_ACCEPTED.md` (PASS)
