# Samakia Fabric – Operations Guide

This document describes **day-to-day operational procedures** for Samakia Fabric.

It is intended for:
- Operators
- SREs
- Platform engineers
- Automated agents performing operational tasks

This is a **runbook**, not a tutorial.

---

## Operational Scope

Samakia Fabric operations cover:
- Golden image lifecycle
- Terraform infrastructure lifecycle
- Ansible bootstrap and configuration
- Controlled recovery procedures

This document does NOT cover:
- Application operations
- Kubernetes workloads
- CI/CD pipelines beyond the GitOps workflows described in Phase 4
- Observability stacks

## Operator UX (canonical)

Operator commands and task flows are defined in:

- `docs/operator/cookbook.md` (canonical command cookbook)
- `docs/operator/exposure.md` (governed exposure choreography)
- `docs/operator/runtime-ops.md` (runtime operations and signal classification)
- `docs/operator/slo-ownership.md` (SLO ownership and escalation rules)
- `docs/operator/runner-modes.md`
- `docs/operator/ssh-trust.md`
- `docs/operator/networking.md`
- `docs/operator/safety-model.md`
- `docs/operator/evidence-and-artifacts.md`
- `docs/operator/observability.md`
- `docs/observability/policy.md`

Consumer workflows live in:

- `docs/consumers/catalog.md`
- `docs/consumers/quickstart.md`
- `docs/consumers/variants.md`

Tenant binding workflows live in:

- `docs/tenants/README.md`
- `docs/tenants/onboarding.md`
- `docs/tenants/consumer-bindings.md`
- `docs/bindings/README.md`
- `docs/bindings/secrets.md`
- `docs/bindings/verification.md`
- Evidence packets (gitignored) are written under `evidence/tenants/<tenant>/<UTC>/`.
- Execute mode is **guarded and opt-in**; see the operator cookbook for `tenants.plan`,
  `tenants.apply`, and DR dry-run/execute flows.
- Binding contracts and connection manifests:
  - Validate: `make bindings.validate TENANT=all`
  - Render: `make bindings.render TENANT=all`
  - Verify (offline, read-only): `make bindings.verify.offline TENANT=all`
  - Verify (live, guarded): `VERIFY_MODE=live VERIFY_LIVE=1 make bindings.verify.live TENANT=<tenant>`
  - Apply (guarded): `make bindings.apply TENANT=<tenant> WORKLOAD=<id>`
- Binding secrets (Phase 12 Part 2; operator-controlled):
  - Default backend is Vault; file backend requires explicit override for write paths.
  - Inspect refs (read-only): `make bindings.secrets.inspect TENANT=all`
  - Materialize (dry-run): `make bindings.secrets.materialize.dryrun TENANT=all`
  - Materialize (execute, guarded):
    - `MATERIALIZE_EXECUTE=1 BIND_SECRETS_BACKEND=file BIND_SECRET_INPUT_FILE=./secrets-input.json make bindings.secrets.materialize TENANT=<tenant>`
  - Rotation plan (read-only): `make bindings.secrets.rotate.plan TENANT=all`
  - Rotation dry-run: `make bindings.secrets.rotate.dryrun TENANT=all`
  - Rotation execute (guarded):
    - `ROTATE_EXECUTE=1 ROTATE_REASON="..." BIND_SECRETS_BACKEND=file ROTATE_INPUT_FILE=./rotation-input.json make bindings.secrets.rotate TENANT=<tenant>`
- Proposal workflow (Phase 12 Part 4; optional, operator-controlled):
  - Submit proposal (intake only): `make proposals.submit FILE=examples/proposals/add-postgres-binding.yml`
  - Validate proposal: `make proposals.validate PROPOSAL_ID=<id>`
  - Review bundle (diff + impact): `make proposals.review PROPOSAL_ID=<id>`
  - Approve (guarded): `OPERATOR_APPROVE=1 APPROVER_ID="ops-01" make proposals.approve PROPOSAL_ID=<id>`
  - Reject + archive (guarded): `OPERATOR_REJECT=1 APPROVER_ID="ops-01" make proposals.reject PROPOSAL_ID=<id>`
  - Apply dry-run: `APPLY_DRYRUN=1 make proposals.apply PROPOSAL_ID=<id>`
  - Apply execute (guarded): `PROPOSAL_APPLY=1 BIND_EXECUTE=1 make proposals.apply PROPOSAL_ID=<id>`
  - Prod approvals require signed decisions; apply verifies decision signatures for prod.
- Self-service proposals (Phase 15 Part 1; proposal-only):
  - Submit proposal: `make selfservice.submit FILE=examples/selfservice/example.yml`
  - Validate proposal: `make selfservice.validate PROPOSAL_ID=<id>`
  - Read-only plan preview: `make selfservice.plan PROPOSAL_ID=<id>`
  - Review bundle (diff + impact + plan): `make selfservice.review PROPOSAL_ID=<id>`
  - No apply paths are exposed; execution remains operator-controlled.
- Self-service governance (Phase 15 Part 2; design-only):
  - Proposal lifecycle: `docs/selfservice/proposal-lifecycle.md`
  - Approval contract: `contracts/selfservice/approval.schema.json`
  - Delegation contract: `contracts/selfservice/delegation.schema.json`
  - Execution mapping: `docs/selfservice/execution-mapping.md`
  - Audit model: `docs/selfservice/audit-model.md`
  - Operator UX: `docs/operator/selfservice-approval.md`
- Autonomy guardrails (Phase 15 Part 3; design-only):
  - Autonomy levels: `docs/selfservice/autonomy-levels.md`
  - Risk budgets: `docs/selfservice/risk-budgets.md`
  - Stop rules: `docs/selfservice/stop-rules.md`
  - Guardrail mapping: `docs/selfservice/guardrail-mapping.md`
  - Accountability: `docs/selfservice/accountability.md`
  - Operator governance: `docs/operator/selfservice-governance.md`
- Self-service UX + trust (Phase 15 Part 4; design-only):
  - Tenant UX contract: `docs/selfservice/tenant-ux-contract.md`
  - Trust boundaries: `docs/selfservice/trust-boundaries.md`
  - UX safeguards: `docs/selfservice/ux-safeguards.md`
  - Autonomy unlock criteria: `docs/selfservice/autonomy-unlock-criteria.md`
  - Conflict resolution: `docs/selfservice/conflict-resolution.md`
  - Operator UX: `docs/operator/selfservice-governance-ux.md`
- Self-service governance closure (Phase 15 Part 5; design-only):
  - Governance model: `docs/selfservice/governance-model.md`
  - Risk ledger: `docs/selfservice/risk-ledger.md`
  - Exceptions: `docs/selfservice/exceptions.md`
  - Phase interactions: `docs/selfservice/phase-interactions.md`
  - Phase 15 acceptance plan: `acceptance/PHASE15_ACCEPTANCE_PLAN.md`
  - Phase 15 lock marker: `acceptance/PHASE15_ACCEPTED.md`
- Drift awareness (Phase 12 Part 5; read-only):
  - Detect tenant drift (non-blocking): `TENANT=all DRIFT_OFFLINE=1 DRIFT_NON_BLOCKING=1 DRIFT_FAIL_ON=none make drift.detect`
  - Emit tenant summaries: `TENANT=all make drift.summary`
  - Acceptance gate: `make phase12.part5.accept`
- Phase 12 closure (release readiness packet):
  - One-page flow: `docs/operator/phase12-exposure.md`
  - CI-safe umbrella: `TENANT=all make phase12.accept`
  - Packet only: `TENANT=all make phase12.readiness.packet`
  - Acceptance markers: `make phase12.part6.accept`
- Phase 13 exposure (governed choreography; operator-controlled):
  - Semantics: `docs/exposure/semantics.md`
  - Change windows + signing: `docs/exposure/change-window-and-signing.md`
  - Rollback: `docs/exposure/rollback.md`
  - Canary runbook + prerequisites: `docs/exposure/canary.md`
  - Phase 17 Step 4 canary execution evidence: `evidence/exposure-canary/canary/sample/2026-01-04T04:40:26Z`
  - Part 1 (plan-only):
    - Validate policy: `make exposure.policy.check`
    - Plan exposure: `ENV=samakia-dev TENANT=canary WORKLOAD=sample make exposure.plan`
    - Explain decision: `ENV=samakia-dev TENANT=canary WORKLOAD=sample make exposure.plan.explain`
    - Entry check: `make phase13.part1.entry.check`
  - Part 2 (approve/apply/verify/rollback):
    - Approve: `PLAN_EVIDENCE_REF=... APPROVER_ID=... EXPOSE_REASON=... make exposure.approve`
    - Apply dry-run: `APPROVAL_DIR=... TENANT=... WORKLOAD=... ENV=... make exposure.apply`
    - Apply execute (guarded): `EXPOSE_EXECUTE=1 EXPOSE_REASON=... APPROVER_ID=... make exposure.apply`
    - Verify (offline): `TENANT=... WORKLOAD=... ENV=... make exposure.verify`
    - Verify live (guarded): `VERIFY_LIVE=1 TENANT=... WORKLOAD=... ENV=... make exposure.verify`
    - Rollback dry-run: `ROLLBACK_REASON=... ROLLBACK_REQUESTED_BY=... make exposure.rollback`
    - Rollback execute (guarded): `ROLLBACK_EXECUTE=1 ROLLBACK_REASON=... ROLLBACK_REQUESTED_BY=... make exposure.rollback`
    - Entry check: `make phase13.part2.entry.check`
    - Acceptance (dry-run only): `CI=1 make phase13.part2.accept`
- Phase 14 runtime operations (read-only):
  - Signal taxonomy: `docs/runtime/signal-taxonomy.md`
  - Incident lifecycle: `docs/runtime/incident-lifecycle.md`
  - Operator runbook: `docs/operator/runtime-ops.md`
  - SLO measurement: `docs/operator/slo.md`
  - SLO ownership: `docs/operator/slo-ownership.md`
  - Runtime evaluation (read-only):
    - `make runtime.evaluate TENANT=<id|all>`
    - `make runtime.status TENANT=<id|all>`
  - SLO evaluation (read-only):
    - `make slo.ingest.offline TENANT=<id|all>`
    - `make slo.evaluate TENANT=<id|all>`
    - `make slo.alerts.generate TENANT=<id|all>`
  - Alert delivery (guarded; no remediation):
    - `make alerts.validate`
    - `ALERTS_ENABLE=1 ALERT_SINK=slack make alerts.deliver TENANT=<id|all>`
  - Incident records (read-only tracking):
    - `make incidents.open INCIDENT_ID=... TENANT=... WORKLOAD=... SIGNAL_TYPE=... SEVERITY=... OWNER=... EVIDENCE_REFS=...`
    - `make incidents.update INCIDENT_ID=... UPDATE_SUMMARY=...`
    - `make incidents.close INCIDENT_ID=... RESOLUTION_SUMMARY=...`
- Milestone Phase 1–12 verification (release manager, read-only):
  - Verify: `make milestone.phase1-12.verify`
  - Lock: `make milestone.phase1-12.lock`
  - Evidence: `evidence/milestones/phase1-12/<UTC>/`

VM image workflows live in:

- `docs/images/README.md`

Substrate executor design (Phase 11) lives in:

- `docs/substrate/README.md`
- `docs/substrate/capacity.md`
- `docs/substrate/slo-failure-semantics.md`
- `docs/substrate/observability.md`
- `contracts/substrate/`
- Default drift alert routing (evidence-only):
  - `contracts/alerting/routing.yml`
  - `make substrate.alert.validate`
  - `make phase11.part5.routing.accept`
- Plan-only executor workflow (read-only):
  - `make substrate.plan TENANT=all`
  - `make substrate.dr.dryrun TENANT=all`
  - `make substrate.verify TENANT=all`
  - `make substrate.observe TENANT=all`
  - `make substrate.observe.compare TENANT=all`
- Guarded execute workflow (explicit opt-in; never in CI):
  - `make substrate.apply TENANT=all ENV=samakia-dev`
  - `make substrate.dr.execute TENANT=all ENV=samakia-dev`
- Pre-exposure hardening gate (read-only; required before Phase 12 exposure):
  - JSON checklist source: `hardening/checklist.json`
  - Auto-generated checklist: `acceptance/PHASE11_HARDENING_ENTRY_CHECKLIST.md`
  - Operator view: `docs/operator/hardening.md`
  - `make phase11.hardening.entry.check`
  - `make phase11.hardening.accept`

### TLS policy
- Default: strict verification
- Proxmox internal CA: install CA into the runner host trust store (no insecure flags)
- CI environments MUST use valid CA

## Runner Host Setup (Phase 1)

Samakia Fabric assumes Terraform and Ansible run from a trusted **runner host** with:
- Proxmox internal CA installed in the host trust store (strict TLS, no bypass flags)
- A canonical local environment file with API tokens and backend configuration

### Repository root invariant (scripts)

Operational scripts are written to be bootstrap-safe and must not rely on the current working directory.

Set the repo root once per shell session (the Makefile exports this automatically):

```bash
export FABRIC_REPO_ROOT="$(git rev-parse --show-toplevel)"
```

### Install Proxmox internal CA (runner host)

```bash
bash "$FABRIC_REPO_ROOT/ops/scripts/install-proxmox-ca.sh"
```

### Install runner env file (canonical)

Creates `~/.config/samakia-fabric/env.sh` with `chmod 600` (local-only; never committed):

```bash
bash "$FABRIC_REPO_ROOT/ops/scripts/runner-env-install.sh"
```

CI/automation (non-interactive):

```bash
RUNNER_MODE=ci bash "$FABRIC_REPO_ROOT/ops/scripts/runner-env-install.sh" --non-interactive
```

Validate (presence-only; secrets are never printed):

```bash
bash "$FABRIC_REPO_ROOT/ops/scripts/runner-env-check.sh"
```

### Runner mode contract

Samakia Fabric enforces a runner contract to keep automation deterministic.

- `RUNNER_MODE=ci` (default): prompts are forbidden; scripts must fail fast.
- `RUNNER_MODE=operator`: prompts allowed only where documented and explicitly opted in.
- `CI=1` enforces `RUNNER_MODE=ci`; if it prompts in CI, it is a bug.
- For CI or automation, pass `--non-interactive` where supported (for example, `runner-env-install.sh`).

See `docs/operator/runner-modes.md` for details and usage examples.

### Install MinIO/S3 backend CA (only if required)

If your backend uses an internal CA not already trusted by the host:

```bash
bash "$FABRIC_REPO_ROOT/ops/scripts/install-s3-backend-ca.sh"
```

---

## Remote State Backend (MinIO HA)

Samakia Fabric uses a remote S3-compatible backend (MinIO) for Terraform state and locking (`use_lockfile = true`).

### LAN endpoint vs management IP policy (canonical)

- **Service endpoints on LAN are VIP-only**:
  - DNS VIP: `192.168.11.100`
  - MinIO VIP: `192.168.11.101`
- **Management IPs (ops-only; never service endpoints)**:
- MinIO edges: `minio-edge-1=192.168.11.102`, `minio-edge-2=192.168.11.103`
- DNS edges: `dns-edge-1=192.168.11.111`, `dns-edge-2=192.168.11.112`
- **Collision rule**: `.100/.101/.102/.103` are reserved for DNS/MinIO VIP + MinIO edge mgmt only.

### Shared VLAN IP/VIP allocation contract

Shared VLAN addresses (VLAN120) must be allocated exclusively from the
authoritative contract:
- `contracts/network/ipam-shared.yml`
- `docs/network/ipam-shared.md`

VIPs are registry-only, and DNS must resolve to proxy nodes (not VIPs).

One-command deployment (non-interactive; requires runner env for Proxmox token + bootstrap SSH key):

```bash
make minio.up ENV=samakia-minio
```

### MinIO bootstrap lifecycle (canonical)

The MinIO environment is the Terraform backend provider, so it **must not depend on itself** at bootstrap time.

#### Terraform Backend Bootstrap Invariant

Invariant:
- `ENV=samakia-minio` must always start with **local state**:
  - `terraform init -backend=false`
- Only after MinIO is deployed and accepted may the state be migrated to remote S3.

Implementation detail (no manual steps):
- The Makefile bootstraps Terraform from a runner-local workspace that copies the env files **excluding** `backend.tf` (backend remains in Git), because Terraform cannot `plan/apply` against an uninitialized `backend "s3"` block.
- The Makefile exports `TF_VAR_fabric_repo_root` so Terraform `local-exec` can run repo scripts via absolute paths during bootstrap (no cwd/relative-path assumptions).
- Proxmox SDN primitives are created/validated via token-auth API calls; if the SDN plane does not exist, the token must have `SDN.Allocate` or an operator must pre-create the SDN plane first. Proxmox SDN changes are **not usable until applied** cluster-wide (`PUT /cluster/sdn`); Samakia Fabric automation runs this apply step when needed (or when explicitly forced).
  - Terraform `local-exec` SDN ensure hooks run with `--apply` so SDN changes become usable immediately after `terraform apply` (no manual `/cluster/sdn` apply step).

Operational flow (non-interactive):
- `make backend.configure`
- `make minio.tf.apply ENV=samakia-minio` (local state; `-backend=false`)
- `make minio.ansible.apply ENV=samakia-minio`
- `make minio.accept`
- `make minio.state.migrate ENV=samakia-minio` (one-time migration to S3 backend)

Non-interactive apply note:
- `make minio.up` runs Terraform apply with `CI=1` to avoid interactive approval prompts (adds `-auto-approve`).
- If you want an interactive approval gate, run `make minio.tf.plan` then `make minio.tf.apply` without `CI=1`.

Dry-run (no infra mutation):

```bash
DRY_RUN=1 make minio.up ENV=samakia-minio
```

This flow:
- Generates runner-local backend credentials and CA material under `~/.config/samakia-fabric/` (never committed).
- Installs the backend CA into the runner host trust store (strict TLS; requires non-interactive sudo).
- Applies Terraform (bootstrap-local state), bootstraps hosts, configures MinIO cluster + HAProxy VIP, and runs acceptance.
- Migrates the `samakia-minio` Terraform state into the remote backend.

After MinIO is up, initialize other env backends (per env):

```bash
ENV=samakia-prod make tf.backend.init
ENV=samakia-dns  make tf.backend.init
```

DNS becomes unblocked after the backend is available:

```bash
make dns.up ENV=samakia-dns
```

### MinIO SDN Acceptance

Validates the MinIO **stateful SDN plane** (zminio/vminio/VLAN140) and the expected LXC wiring signals in a **read-only**, **non-destructive** way.

```bash
ENV=samakia-minio make minio.sdn.accept
```

Prerequisite:
- The runner’s Proxmox API token must have permission to read SDN primitives, and the SDN plane must already exist.
- If `zminio` does not exist and your token lacks `SDN.Allocate`, the test will fail loudly by design (the plane must be created by an operator with `SDN.Allocate`).

What it checks (best-effort):
- Proxmox SDN primitives exist and match the contract (zone/vnet/subnet/gateway VIP).
- MinIO CTs are VLAN-only (no LAN bridge attached) and default-route via `10.10.140.1` (when CT configs exist).
- MinIO edges are dual-homed and provide the VLAN gateway VIP + NAT readiness (when SSH is reachable).

### MinIO Cluster Convergence Acceptance

Validates the MinIO distributed cluster is **formed and healthy** after `make minio.up ENV=samakia-minio`.

```bash
ENV=samakia-minio make minio.converged.accept
```

What it checks (read-only):
- VIP TLS endpoints: `https://192.168.11.101:9000` (S3) and `https://192.168.11.101:9001` (console) respond with strict TLS.
- HA signals: keepalived/haproxy active on both edges; exactly one VIP holder; all backends healthy via edge.
- Cluster membership: `mc admin info` indicates 3 MinIO nodes and no offline/healing/rebalancing signals (best-effort parsing).
- Control-plane invariants: Terraform backend bucket exists; `samakia-minio` tfstate object exists post-migration; anonymous access disabled; terraform user is not admin.

### MinIO Quorum Guard (detect-only)

Detect-only gate that answers:
“Is the MinIO backend safe enough to rely on it for Terraform remote state writes (and state migration)?”

```bash
ENV=samakia-minio make minio.quorum.guard
```

Output:
- Prints a secrets-safe summary to stdout (PASS/WARN/FAIL).
- Writes an auditor-grade report to `audit/minio-quorum-guard/<UTC>/report.md` (no credentials/tokens are written).

Meaning:
- **PASS**: safe to proceed with Terraform state writes/migration (subject to normal operator governance).
- **WARN**: degraded; safe for reads only; blocks state migration and any flow requiring safe writes.
- **FAIL**: unsafe; blocks.

Hard gates:
- `make minio.state.migrate ENV=samakia-minio`
- `make minio.up ENV=samakia-minio` (before state migration)
- `make dns.up ENV=samakia-dns` (DNS uses the MinIO remote backend)

### MinIO Edge Failure Simulation

Deterministic, reversible acceptance-level simulation that stops `haproxy` + `keepalived` on **one** MinIO edge and verifies the VIP remains available.

```bash
make minio.failure.sim ENV=samakia-minio EDGE=minio-edge-1
```

Safety guarantees:
- Stops only `haproxy` + `keepalived` on the selected edge (no reboots, no CT deletion, no Terraform state changes).
- Attempts recovery automatically if a post-check fails.
- Uses strict TLS and strict SSH host key checking (no insecure flags).

### MinIO Terraform Backend Smoke Test (real init+plan)

Hard gate that answers:
“Can Terraform initialize and plan against the real MinIO S3 backend with strict TLS and lockfiles?”

```bash
ENV=samakia-minio make minio.backend.smoke
```

This test:
- Creates an isolated ephemeral workspace under `_tmp/` (auto-cleaned).
- Runs `terraform init` (remote backend; no `-backend=false`).
- Runs `terraform plan` (no resources; expects “No changes”).
- Verifies backend metadata indicates `s3`, endpoint matches `https://192.168.11.101:9000`, and `use_lockfile=true`.
- Requires observing state lock activity during `plan`.

This gate is enforced automatically before:
- `make minio.state.migrate ENV=samakia-minio`
- any non-minio `make tf.apply ENV=<env>`
- `make dns.up ENV=samakia-dns`


---

## Break-glass / Recovery

If you lose SSH access to a container, follow `OPERATIONS_BREAK_GLASS.md`.
This runbook is contract-safe: no root SSH re-enablement, no passwords, strict TLS, and no DNS dependency.

---

## Promotion Flow

Production upgrades are Git-driven and version-pinned:
- Image (`ubuntu-24.04-lxc-rootfs-vN.tar.gz`) → Proxmox template (`vztmpl/...-vN.tar.gz`) → Terraform env pin.

See `OPERATIONS_PROMOTION_FLOW.md`.

---

## DNS Infrastructure (infra.samakia.net)

Samakia Fabric DNS is a dedicated substrate:
- Single DNS endpoint for the entire estate: `192.168.11.100` (LAN VIP)
- Dual `dns-edge` nodes provide the VIP via VRRP and act as VLAN gateways (NAT egress)
- PowerDNS Authoritative runs on VLAN-only `dns-auth` nodes (master/slave)

One-command deployment (non-interactive):

```bash
make dns.up ENV=samakia-dns
```

Acceptance (non-interactive):

```bash
make dns.accept
```

Expected behavior:
- Exactly one edge holds `192.168.11.100` at any time.
- Exactly one edge holds VLAN gateway VIP `10.10.100.1` at any time.
- Queries for `infra.samakia.net` are answered authoritatively (dnsdist → PowerDNS).
- All other queries recurse via unbound (dnsdist → unbound).

Notes:
- Proxmox SDN objects for VLAN100 are created/validated during `terraform apply` (token-only via Proxmox API).
- `dns-auth-*` are VLAN-only; Ansible connects via `ProxyJump` through `dns-edge` (no DNS dependency).

---

## Shared Control Plane Services (Phase 2.1)

Shared services provide internal time, PKI, secrets, and observability as reusable primitives.
They run on a dedicated SDN plane (VLAN120, `zshared`/`vshared`, `10.10.120.0/24`).

Service endpoints (VIPs on LAN):
- NTP: `192.168.11.120` (UDP/123)
- Vault: `192.168.11.121` (TLS/8200)
- Observability: `192.168.11.122` (TLS/3000, 9090, 9093, 3100)

Shared edge mgmt IPs (ops-only, SSH allowlisted):
- `ntp-1`: `192.168.11.106`
- `ntp-2`: `192.168.11.107`

One-command deployment (non-interactive):

```bash
make shared.up ENV=samakia-shared
```

Acceptance (read-only):

```bash
make shared.accept ENV=samakia-shared
```

Granular acceptance checks:
- `make shared.sdn.accept ENV=samakia-shared`
- `make shared.ntp.accept ENV=samakia-shared`
- `make shared.vault.accept ENV=samakia-shared`
- `make shared.pki.accept ENV=samakia-shared`
- `make shared.obs.accept ENV=samakia-shared`

Shared observability policy (hard gate; no warnings):

```bash
make shared.obs.policy ENV=samakia-shared
```

Local credentials and CA material (runner-only, never committed):
- Vault init + root token: `~/.config/samakia-fabric/vault/init.json` and `~/.config/samakia-fabric/vault/root-token`
- Shared bootstrap CA (Vault TLS): `~/.config/samakia-fabric/pki/shared-bootstrap-ca.crt`
- Shared PKI CA (Vault PKI): `~/.config/samakia-fabric/pki/shared-pki-ca.crt`
- Shared edge VIP TLS pem: `~/.config/samakia-fabric/pki/shared-edge.pem`
- Grafana admin password: `~/.config/samakia-fabric/grafana/admin-password`

Notes:
- VIPs are the only service endpoints; shared-edge mgmt IPs are ops-only.
- SSH allowlist for shared edges is controlled via `FABRIC_ADMIN_CIDRS` (comma-separated CIDRs).
- No DNS dependency for bootstrap or acceptance (use VIP IPs).

---

## Internal Shared Postgres (Patroni)

Internal Postgres is a shared, HA service used for platform verification and
Phase 17 canary exposure. It is **internal-only** and not tenant-exposed by
default.

Endpoints:
- Primary DNS: `db.internal.shared` (A → `10.10.120.13`, `10.10.120.14`)
- Alias: `db.canary.internal` (CNAME → `db.internal.shared`)
- VIP: `10.10.120.2` (Keepalived on HAProxy nodes; never a DNS target)

Topology (shared VLAN):
- Patroni nodes: `pg-internal-1..3` (`10.10.120.23`–`10.10.120.25`)
- HAProxy nodes: `haproxy-pg-1/2` (`10.10.120.13`, `10.10.120.14`)

HAProxy behavior:
- TCP 5432, TLS passthrough; Postgres handles TLS.
- Backend selection uses Patroni REST (`/patroni` + `/primary`) to route to the leader.
- Stats endpoint is local-only (127.0.0.1).
- Source allowlist: `10.10.120.0/24` plus `FABRIC_ADMIN_CIDRS` (defaults to `192.168.11.0/24`).
- LAN runner access requires the shared edge gateway forward rule (applied via `shared-ntp`).

Secrets (Vault default; no secrets in Git):
- Admin: `platform/internal/postgres/admin`
- App: `platform/internal/postgres/app`
- Canary verify: `tenants/canary/database/sample`

Operations:
```bash
ENV=samakia-shared make postgres.internal.plan
ENV=samakia-shared make postgres.internal.apply
ENV=samakia-shared make postgres.internal.accept
ENV=samakia-shared make postgres.internal.doctor
```

Guarded rebootstrap (destructive; wipes Patroni + etcd data on internal nodes):
```bash
POSTGRES_INTERNAL_RESET=1 ENV=samakia-shared make postgres.internal.apply
```

### Phase 2.2 — Control Plane Correctness & Invariants

Phase 2.2 tightens shared control-plane correctness beyond reachability.
These checks are **read-only** and produce binary PASS/FAIL (no SKIP).

Ingestion acceptance (Loki must show queryable series):

```bash
make shared.obs.ingest.accept ENV=samakia-shared
```

Runtime invariants (systemd active + enabled + restart policy):

```bash
make shared.runtime.invariants.accept ENV=samakia-shared
```

Aggregate Phase 2.2 gate:

```bash
make phase2.2.accept ENV=samakia-shared
```

Notes:
- Runtime invariant checks require passwordless sudo for read-only systemd inspection.
- Ingestion acceptance passes when **either** `systemd-journal` or `varlogs` series are present.

---

## Golden Image Operations (Packer)

### When to Build a New Image

Build a new golden image only when:
- OS base updates are required
- SSH or OS hardening changes are required
- Image hygiene fixes are required (machine-id, host keys)
- Security advisories require it

Do NOT rebuild images for:
- User changes
- Application software
- Environment-specific configuration

### Image Build Procedure

```bash
	make image.build-next
```

Expected artifact:

```text
ubuntu-24.04-lxc-rootfs-v<N>.tar.gz
```

### Image Import to Proxmox

Upload the versioned rootfs artifact to Proxmox as an immutable LXC template (API token-based, no SSH).
Requires: `PM_API_URL`, `PM_API_TOKEN_ID`, `PM_API_TOKEN_SECRET`.

```bash
bash fabric-core/packer/lxc/scripts/upload-lxc-template-via-api.sh ./ubuntu-24.04-lxc-rootfs-v<N>.tar.gz
```

Validate:

```bash
pveam list <storage> | grep ubuntu-24.04
```

Rules:
- Never overwrite an existing template
- Always version images (`v1`, `v2`, `v3`, ...)

---

## VM Golden Image Contracts (Design)

VM golden images are managed as immutable **contracts** (design-only in Phase 8).
Fabric validates contracts and provenance; it does **not** manage VM lifecycle.

Docs:
- `docs/images/README.md`
- `docs/images/vm-golden-images.md`
- `docs/images/image-lifecycle.md`
- `docs/images/image-security.md`
- `docs/images/proxmox-template-registration.md`

Entry check (design validation only):

```bash
make phase8.entry.check
```

Phase 8 Part 1 (validate-only, no Proxmox registration):

```bash
make images.vm.validate.contracts
CI=1 make phase8.part1.accept
```

Phase 8 Part 1.1 (local operator runbook + safe wrappers):

```bash
make image.tools.check
make image.local.validate IMAGE=ubuntu-24.04 VERSION=v1 QCOW2=/path/to/image.qcow2
make image.local.evidence IMAGE=ubuntu-24.04 VERSION=v1 QCOW2=/path/to/image.qcow2
make phase8.part1.1.accept
```

Runbook:
- `docs/images/local-build-and-validate.md`

Phase 8 Part 1.2 (optional toolchain container):

```bash
make image.toolchain.build IMAGE=ubuntu-24.04 VERSION=v1
make image.toolchain.validate IMAGE=ubuntu-24.04 VERSION=v1 QCOW2=/path/to/image.qcow2
make phase8.part1.2.accept
```

Toolchain definition:
- `tools/image-toolchain/`

Phase 8 Part 2 (guarded Proxmox template registration):

```bash
make images.vm.register.policy.check

IMAGE_REGISTER=1 I_UNDERSTAND_TEMPLATE_MUTATION=1 \
REGISTER_REASON="initial vm template register" \
ENV=samakia-dev TEMPLATE_NODE=proxmox1 TEMPLATE_STORAGE=pve-nfs TEMPLATE_VM_ID=9001 \
QCOW2=/path/to/ubuntu-24.04.qcow2 \
make image.template.register IMAGE=ubuntu-24.04 VERSION=v1

ENV=samakia-dev TEMPLATE_NODE=proxmox1 TEMPLATE_STORAGE=pve-nfs TEMPLATE_VM_ID=9001 \
make image.template.verify IMAGE=ubuntu-24.04 VERSION=v1

CI=1 make phase8.part2.accept
```

Runbook:
- `docs/images/proxmox-template-registration.md`

Optional local artifact validation (requires a local qcow2 fixture):

```bash
QCOW2_FIXTURE_PATH=/path/to/image.qcow2 make phase8.part1.accept
```

Local builds are guarded:

```bash
IMAGE_BUILD=1 make image.build IMAGE=ubuntu-24.04 VERSION=v1
```

---

## Terraform Operations

### Where Terraform Is Run

Terraform MUST be executed only from:

```text
fabric-core/terraform/envs/<environment>
```

Never run Terraform inside `modules/`.

### Standard Terraform Workflow

Samakia Fabric uses a remote backend (MinIO/S3) with locking (`use_lockfile = true`).
Backend configuration is **not stored in Git**; it is initialized from runner env vars.

Initialize backend (per environment):

```bash
ENV=samakia-prod make tf.backend.init
```

Optional: migrate existing local state deliberately:

```bash
ENV=samakia-prod MIGRATE_STATE=1 make tf.backend.init
```

Plan/apply (non-interactive defaults, strict locking):

```bash
ENV=samakia-prod make tf.plan
ENV=samakia-prod make tf.apply
```

Destroy/recreate is acceptable and expected when:
- Template changes
- Storage changes
- Immutable attributes change

### Proxmox UI Tags (Terraform-managed metadata)

Terraform is the source of truth for Proxmox tags on LXCs. Tags are compact, deterministic, and semicolon-separated:

- `golden-vN;plane-<plane>;env-<env>;role-<role>`

Operational rules:
- Do not edit tags manually in Proxmox UI (treated as drift).
- `golden-vN` is derived from the pinned template artifact name (`*-vN.tar.gz`).
- Tags must not contain secrets, IPs, or spaces.

### Provider and Permissions

Terraform runs with a delegated Proxmox user.

Terraform MUST NOT:
- Require `root@pam`
- Modify LXC feature flags dynamically

If Terraform fails with permission errors:
- Verify whether the change violates delegated-user constraints
- Do NOT escalate privileges silently

---

## Drift Detection & Audit (read-only)

Run a non-destructive audit that detects:
- Terraform drift via `terraform plan` (no apply)
- Configuration drift via `ansible-playbook playbooks/harden.yml --check --diff` (no mutation)

This produces a timestamped local report under `audit/` (ignored by Git).

```bash
# Requires strict TLS trust (internal CA) and Proxmox API token env vars.
bash ops/scripts/drift-audit.sh samakia-prod
```

Interpretation:
- Any non-empty Terraform plan is “potential drift” and must be remediated via Git change + explicit apply/recreate.
- Any Ansible “would change” indicates policy drift and must be remediated via Ansible changes + deliberate re-run (non-check mode).

---

## Compliance & Signed Audit Exports

Generate immutable compliance snapshots (Terraform drift + Ansible check) and sign them for offline verification:

- `OPERATIONS_COMPLIANCE_AUDIT.md`
- `OPERATIONS_KEY_CUSTODY_DUAL_CONTROL.md` (dual-control / two-person signing)
- `OPERATIONS_EVIDENCE_NOTARIZATION.md` (optional TSA timestamp notarization)
- `OPERATIONS_APPLICATION_COMPLIANCE.md` (application-level compliance overlay)
- `OPERATIONS_POST_INCIDENT_FORENSICS.md` (post-incident forensics packets)
- `OPERATIONS_LEGAL_HOLD_RETENTION.md` (legal hold & retention governance for evidence)
- `OPERATIONS_CROSS_INCIDENT_CORRELATION.md` (cross-incident correlation: timelines + hypotheses, derived artifacts only)

---

## Incident Severity & Evidence Policy

Severity (S0–S4) determines evidence depth and signing requirements (not remediation actions):

- `INCIDENT_SEVERITY_TAXONOMY.md`

---

## Legal Hold & Retention

Legal hold is a **policy state** that overrides operational retention and prevents accidental evidence expiry/deletion (no deletion automation is implemented here).

- `LEGAL_HOLD_RETENTION_POLICY.md`
- `OPERATIONS_LEGAL_HOLD_RETENTION.md`

---

## Security Threat Modeling

Threat modeling is analysis-only and informs prioritization (it does not enforce controls or mutate systems):
- `SECURITY_THREAT_MODELING.md`

Related inputs:
- `INCIDENT_SEVERITY_TAXONOMY.md`
- `COMPLIANCE_CONTROLS.md`
- `OPERATIONS_POST_INCIDENT_FORENSICS.md`
- `OPERATIONS_CROSS_INCIDENT_CORRELATION.md`

---

## HA / Failure Domains

Proxmox HA is enabled deliberately per workload, with explicit placement/failure-domain thinking and operator-run recovery steps.

- `OPERATIONS_HA_FAILURE_DOMAINS.md`
- `OPERATIONS_HA_FAILURE_SIMULATION.md` (GameDays / failure simulation runbook)
- `OPERATIONS_HA_SEMANTICS.md` (HA tiers, failure-domain model, Proxmox HA vs VIP HA)
- `OPERATIONS_GAMEDAYS.md` (Phase 3 Part 2 GameDay framework and procedures)

Read-only validation and evidence:

- `make ha.placement.validate` (placement policy vs inventory; anti-affinity checks)
- `make ha.proxmox.audit` (Proxmox HA resources vs policy expectation)
- `make ha.enforce.check ENV=<env>` (hard gate; blocks plan/apply on violations)
- `make ha.evidence.snapshot` (cluster status, VIP ownership, service readiness, SDN pending)
- `make phase3.part1.accept` (aggregated Phase 3 Part 1 acceptance gate)
- `make phase3.part3.accept` (Phase 3 Part 3 enforcement acceptance gate)

Enforcement overrides (explicit, auditable only):

- `HA_OVERRIDE=1`
- `HA_OVERRIDE_REASON="<text>"`

Overrides are required to proceed with known violations (e.g., single-replica tier1).
They are logged in enforcement output and should be recorded in operational notes.

Placement policy source of truth:

- `fabric-core/ha/placement-policy.yml`

---

## Pre-Release Readiness Audit

Formal Go/No-Go gate that aggregates platform, drift, compliance, incident posture, and risk signals into a signable readiness packet (analysis-only).

- `OPERATIONS_PRE_RELEASE_READINESS.md`

---

## Ansible Operations

### Bootstrap Procedure (New LXC)

1. Terraform creates the container
2. Temporary root SSH access (key-only)
3. Run bootstrap playbook

```bash
ansible-playbook playbooks/bootstrap.yml -u root -e @secrets/authorized_keys.yml
```

`secrets/authorized_keys.yml` must define `bootstrap_authorized_keys` and is not committed.
Bootstrap will fail if keys are missing to avoid lockout.

Verify:
- Non-root user exists
- SSH keys installed
- Passwordless sudo
- Root SSH access disabled

### Normal Configuration Runs

```bash
ansible-playbook playbooks/site.yml
```

Rules:
- Must be idempotent
- Must not assume fresh hosts
- Must not rely on interactive input

---

## SSH Access Model

Rules:
- SSH is key-only
- Password authentication is forbidden
- Root SSH access is temporary
- Long-term access uses a non-root operator user

Validation:

```bash
ssh <user>@<host>
sudo -i
```

Failure to enforce this model is considered a security incident.

---

## GitOps / CI Workflows (Phase 4)

Samakia Fabric integrates infrastructure lifecycle with Git workflows using **read-only-first** CI and **manual, gated apply** for non-prod.

### PR validation (read-only)

Workflow: `.github/workflows/pr-validate.yml`

Runs:
- `make policy.check`
- `pre-commit run --all-files`
- `bash fabric-ci/scripts/lint.sh`
- `bash fabric-ci/scripts/validate.sh`
- `make ha.enforce.check ENV=samakia-prod`

### PR plan evidence (read-only)

Workflow: `.github/workflows/pr-tf-plan.yml`

Runs per env and uploads plan artifacts:
- `make tf.plan ENV=<env>` (or `make minio.tf.plan` for `samakia-minio`)
- Evidence packet: `evidence/ci/plan/<env>/<UTC>/` with `metadata.json`, `terraform-plan.txt`, `manifest.sha256`

### Non-prod apply (manual, gated)

Workflow: `.github/workflows/apply-nonprod.yml` (workflow_dispatch only)

Rules:
- Env allowlist: `samakia-dev`, `samakia-staging` only
- Confirmation phrase required: `I_UNDERSTAND_APPLY_IS_MUTATING`
- Re-runs validation + enforcement before apply
- Produces evidence under `evidence/ci/apply/<env>/<UTC>/`

### Drift detection (read-only)

Workflow: `.github/workflows/drift-detect.yml` (scheduled + manual)

Local equivalent:

```bash
bash ops/scripts/drift-packet.sh samakia-prod
```

Evidence packet output:
- `evidence/drift/<env>/<UTC>/` with `metadata.json`, `terraform-plan.txt`, `ansible-check.txt`, `manifest.sha256`
- Optional signing via `EVIDENCE_SIGN=1 EVIDENCE_GPG_KEY=<fingerprint>`

### App compliance + release readiness packets (manual)

Workflows:
- `.github/workflows/app-compliance.yml`
- `.github/workflows/release-readiness.yml`

Local equivalents:

```bash
bash ops/scripts/app-compliance-packet.sh <env> <service> <service_root> --config <paths.txt>
bash ops/scripts/release-readiness-packet.sh <release-id> <env>
```

Evidence outputs are artifacts only (not committed).

---

## LXC Lifecycle (Replace / Blue-Green)

Preferred operational patterns (deterministic, GitOps-driven):
- Replace in-place (same VMID) for immutable upgrades
- Blue/green (new VMID) for cutovers

Runbook:
- `OPERATIONS_LXC_LIFECYCLE.md`

Make targets (guidance; never auto-apply):

```bash
ENV=samakia-prod make ops.replace.inplace
ENV=samakia-prod make ops.bluegreen.plan
```

SSH trust rotation after replace/recreate (never disable StrictHostKeyChecking):

```bash
make ssh.trust.rotate HOST=<ip>
make ssh.trust.verify HOST=<ip>
```

---

## Failure and Recovery Scenarios

### Terraform Apply Failure

Steps:
1. Do NOT re-run blindly
2. Read the error
3. Determine the cause:
   - Permission issue
   - API normalization issue
   - Immutable attribute change
4. Fix configuration
5. Re-run `terraform plan`

### Broken Container

Preferred recovery:
1. Destroy container via Terraform
2. Recreate from golden image
3. Re-run Ansible

Manual repair inside containers is discouraged.

### SSH Lockout

If locked out:
1. Access via Proxmox console
2. Fix SSH configuration
3. Re-apply Ansible bootstrap

Never re-enable password authentication as a workaround.

---

## State Management

Terraform state:
- Must be treated as critical data
- Must not be edited manually
- Remote state (S3/MinIO) is the canonical model (Phase 1)

State loss recovery:
- Re-import resources where possible
- Reconcile state carefully
- Avoid force-destroy without understanding impact

---

## Logging and Auditing

Operational logs include:
- Terraform plan/apply output
- Ansible playbook output
- Proxmox task logs

All destructive actions should be traceable via:
- Git history
- Terraform state history
- Proxmox task logs

Minimum audit trail guidance:
- SSH auth events via `/var/log/auth.log` or `journalctl -u ssh`
- Privileged commands via `sudo` entries in auth logs
- Service unit logs via `journalctl -u <service>`

See `OPERATIONS_AUDIT_LOGGING.md` for retention guidance and evidence export.

---

## Secrets Interface (Vault default)

Default backend is **Vault** (HA, shared control plane). The offline encrypted
file backend is an explicit exception for bootstrap/CI/local use. Set
`SECRETS_BACKEND=file` explicitly for exceptions.
Runtime defaults now resolve to Vault; no secrets were migrated.

Vault access is **shared-VLAN only**. Operators must use a shared-VLAN runner
or an explicit SSH port-forward; do not assume off-VLAN access. See
`docs/security/vault-access.md`.

Live verification now validates required secret fields and fails fast before
any TCP/TLS probes if credentials are malformed or empty. Phase 17 canary
verification must stop on these failures before acceptance.

Commands:
```bash
# Show configuration (no secrets)
make secrets.doctor

# Fetch a value (Vault default)
SECRETS_BACKEND=vault VAULT_ADDR=https://vault.example \
  VAULT_TOKEN=... ops/secrets/secrets.sh get <key> [field]
```

Encrypted file format:
- AES-256-CBC with PBKDF2
- JSON object (keys at top-level)
- Stored under `~/.config/samakia-fabric/secrets.enc`

File mode (explicit exception):
```bash
SECRETS_BACKEND=file SECRETS_PASSPHRASE_FILE=~/.config/samakia-fabric/secrets-passphrase \
  ops/secrets/secrets.sh list
```

---

## SSH Key Rotation (operator + break-glass)

Dry-run (read-only):
```bash
make ssh.keys.dryrun
```

By default this is **local/offline** and computes diffs using files only.
If no operator keys file is configured, the dry-run uses a temporary sample key
and reports this in the output. For real rotation, set `OPERATOR_KEYS_FILE`.

Optional remote inspection (requires inventory access and strict host key trust):
```bash
SSH_DRYRUN_MODE=remote make ssh.keys.dryrun
```

Execute (guarded):
```bash
ROTATE_EXECUTE=1 make ssh.keys.rotate
```

Break-glass rotation requires explicit acknowledgement:
```bash
ROTATE_EXECUTE=1 BREAK_GLASS=1 I_UNDERSTAND=1 make ssh.keys.rotate
```

Evidence packets are written under:
`evidence/security/ssh-rotation/<UTC>/`

Rollback guidance:
- Restore the previous `authorized_keys` file on the runner.
- Re-run rotation with `ROTATE_EXECUTE=1` to re-apply.

Policy reference:
- `ops/security/ssh/break-glass-policy.md`

---

## Firewall Profiles (default-off)

Profiles:
- `baseline` (minimal safe allowlist)
- `hardened` (stricter allowlist)

Dry-run (syntax only):
```bash
make firewall.dryrun FIREWALL_PROFILE=baseline
```

Apply (guarded, default-off):
```bash
FIREWALL_ENABLE=1 FIREWALL_EXECUTE=1 make firewall.apply FIREWALL_PROFILE=baseline
```

---

## Compliance Profile Evaluation

Evaluate baseline or hardened profile (read-only):
```bash
make compliance.eval PROFILE=baseline
make compliance.eval PROFILE=hardened
```

Evidence packets are written under:
`evidence/compliance/<profile>/<UTC>/`

---

## Platform Consumers (Phase 6 — Contracts + Validation)

Phase 6 provides consumer contracts and **read-only** validation (no deployments):
- Contracts: `contracts/consumers/`
- Docs: `docs/consumers/README.md`
- Entry check: `make phase6.entry.check`
- Contract validation: `make consumers.validate`
- HA readiness check: `make consumers.ha.check`
- Disaster wiring check: `make consumers.disaster.check`
- GameDay mapping check: `make consumers.gameday.mapping.check`
- GameDay execute policy check: `make consumers.gameday.execute.policy.check`
- GameDay dry-run (safe): `make consumers.gameday.dryrun`
- Readiness evidence: `make consumers.evidence`
- Bundle generation: `make consumers.bundle`
- Bundle validation: `make consumers.bundle.check`
- Acceptance gate: `make phase6.part1.accept`
- Phase 6 Part 2 acceptance: `make phase6.part2.accept`
- Phase 6 Part 3 acceptance: `make phase6.part3.accept`

Evidence packets are written under:
`evidence/consumers/<type>/<variant>/<UTC>/`

Execute-mode consumer GameDays are **opt-in** and allowlisted for dev/staging
only. Maintenance window and signing rules are documented in
`OPERATIONS_GAMEDAYS.md`.

---

## Change Management

All changes must be:
- Code-driven
- Version-controlled
- Reviewed

Emergency changes:
- Must be documented after the fact
- Must be reconciled back into code

“No manual-only fixes” is a hard rule.

---

## Operational Anti-Patterns (Do Not Do)

- Editing containers manually
- Running Terraform as `root@pam`
- Baking users into images
- Hot-patching Proxmox outside code
- Using passwords for SSH
- Treating containers as pets

---

## Acceptance & Verification (Phase 1)

Run the Phase 1 acceptance suite from repo root (safe output; no secrets printed):

```bash
ENV=samakia-prod make phase1.accept
```

## Acceptance & Verification (Phase 0)

Phase 0 is verified with static checks only (no infrastructure mutation):

```bash
make phase0.accept
```

This runs:
- `bash fabric-ci/scripts/lint.sh`
- `bash fabric-ci/scripts/validate.sh`
- env parity checks (dev/staging/prod shape)
- runner env checks (strict TLS + token-only)
- inventory parse + DHCP/IP sanity
- Terraform validate + plan (`-input=false`)

## Acceptance & Verification (Phase 2)

Phase 2 acceptance validates SDN planes and platform services (read-only):

```bash
make phase2.accept
```

Individual checks (read-only):
```bash
make dns.sdn.accept ENV=samakia-dns
make dns.accept
make minio.sdn.accept ENV=samakia-minio
make minio.converged.accept ENV=samakia-minio
make minio.quorum.guard ENV=samakia-minio
make minio.backend.smoke ENV=samakia-minio
```

## Acceptance & Verification (Phase 5)

Phase 5 acceptance validates security guardrails and compliance evaluation (read-only):

```bash
make phase5.entry.check
make phase5.accept
```

---

## AI Operations (Phase 7)

AI participation is **read-only by default** and must follow the allowlist and guardrails.

### Plan review packets (read-only)

```bash
PLAN_PATH=/path/to/terraform-plan.txt ENV=samakia-prod make ai.plan.review
```

Outputs are written under:
`evidence/ai/plan-review/<env>/<UTC>/`

### 03:00-safe allowlist and runbook checks

```bash
make ai.safe.index.check
make ai.runbook.check
```

### Safe-run wrapper (read-only default)

```bash
bash ops/scripts/safe-run.sh policy.check --dry-run
```

### Controlled remediation (opt-in, guarded)

Remediation requires explicit guards and maintenance windows:

```bash
AI_REMEDIATE=1 \
AI_REMEDIATE_REASON="ticket-1234: safe rollback" \
ENV=samakia-staging \
MAINT_WINDOW_START=2026-01-20T02:00:00Z \
MAINT_WINDOW_END=2026-01-20T03:00:00Z \
I_UNDERSTAND_MUTATION=1 \
bash ops/ai/remediate/remediate.sh --target policy.check --execute
```

Evidence is written under:
`evidence/ai/remediation/<env>/<UTC>/`

### Phase 7 acceptance (read-only)

```bash
make phase7.entry.check
make phase7.accept
```

---

## AI Analysis (Phase 16)

AI analysis is **advisory only**. It cannot execute actions or apply changes.
Governance and stop rules are documented in:
- `docs/ai/governance.md`
- `docs/ai/stop-rules.md`
- `docs/ai/risk-ledger.md`

Risk ledger entries are stored under:
`evidence/ai/risk-ledger/`

Kill switches (operator-only):

```bash
export AI_ANALYZE_DISABLE=1
export AI_ANALYZE_BLOCK_TYPES="plan_review,change_impact"
export AI_ANALYZE_BLOCK_MODELS="gpt-oss:20b"
```

Operator entrypoints (read-only, no network):

```bash
bash ops/ai/ai.sh doctor
bash ops/ai/ai.sh route ops.analysis
```

Unified operator entrypoint:

```bash
bash ops/ai/ops.sh doctor
```

AI indexing (offline default):

```bash
make ai.index.offline TENANT=platform SOURCE=docs
```

Live indexing requires explicit guards:

```bash
AI_INDEX_EXECUTE=1 \
AI_INDEX_REASON="ticket-123: refresh docs" \
QDRANT_ENABLE=1 \
OLLAMA_ENABLE=1 \
make ai.index.live TENANT=platform SOURCE=docs
```

MCP services (read-only context):

```bash
make ai.mcp.doctor
make ai.mcp.repo.start
make ai.mcp.evidence.start
make ai.mcp.observability.start
make ai.mcp.runbooks.start
make ai.mcp.qdrant.start
```

Live MCP access is guarded (never in CI):
- Observability: `OBS_LIVE=1`
- Qdrant: `QDRANT_LIVE=1`

AI analysis (evidence-bound, read-only by default):

```bash
make ai.analyze.plan FILE=examples/analysis/drift_explain.yml
```

Guarded live run (operator-only):

```bash
AI_ANALYZE_EXECUTE=1 make ai.analyze.run FILE=examples/analysis/drift_explain.yml
```

Evidence output:
`evidence/ai/analysis/<analysis_id>/<UTC>/`

Evidence index:

```bash
bash ops/ai/evidence/rebuild-index.sh
bash ops/ai/evidence/validate-index.sh
```

Documentation:
- `docs/operator/ai.md`
- `docs/operator/ai-analysis.md`
- `docs/operator/ai-operations.md`
- `docs/ai/overview.md`
- `docs/ai/provider.md`
- `docs/ai/routing.md`
- `docs/ai/indexing.md`
- `docs/ai/mcp.md`
- `docs/ai/analysis.md`
- `docs/ai/examples.md`
- `docs/ai/operations.md`
- `docs/ai/governance.md`
- `docs/ai/stop-rules.md`
- `docs/ai/risk-ledger.md`

---

## AI Invariants (Phase 16 Lock)

AI behavior is locked as a platform invariant and remains advisory-only.
Authoritative statements live in:
- `contracts/ai/INVARIANTS.md`
- `docs/platform/PLATFORM_MANIFEST.md` (AI capability statement)

Any expansion of AI capabilities requires a new Phase (>= 17), an ADR, and an
acceptance plan. The phase-boundary policy blocks unapproved scope changes.

---

## Phase 17 Conditional Autonomy (Design Only)

Phase 17 documents a **conditional, bounded autonomy** model only. It does not
enable execution. Autonomy remains opt-in, scoped, reversible, and guarded by
kill switches.

References:
- `contracts/ai/autonomy/action.schema.json`
- `docs/ai/autonomy-safety.md`
- `docs/ai/autonomy-rollout.md`
- `docs/ai/autonomy-audit.md`

---

## Operational Philosophy

Samakia Fabric follows a rebuild-over-repair philosophy.

If a system breaks:
- Replace it
- Rebuild it
- Reapply configuration

This reduces entropy and operational risk.

---

## Final Notes

Samakia Fabric is designed for calm operations.

If an operational action feels rushed or unclear:
- Stop
- Read the documentation
- Fix the process, not the symptom
