# Samakia Fabric – MinIO HA Backend + DNS Infrastructure (Implementation Review)

This document records what was implemented for the **Terraform remote state backend (MinIO HA)** and the **DNS infrastructure**, and how to run them **end-to-end**.

## MinIO HA Backend — What was implemented

- **Terraform env**: `fabric-core/terraform/envs/samakia-minio/`
  - Proxmox **SDN stateful VLAN plane** ensure step (zminio/vminio/VLAN140 + `10.10.140.0/24`, gw VIP `10.10.140.1`) via API-token-only script `ops/scripts/proxmox-sdn-ensure-stateful-plane.sh`.
  - Five LXCs with deterministic placement + static IPs:
    - `minio-edge-1` (`proxmox1`): LAN `192.168.11.102`, VLAN `10.10.140.2`
    - `minio-edge-2` (`proxmox2`): LAN `192.168.11.103`, VLAN `10.10.140.3`
    - `minio-1` (`proxmox1`): VLAN `10.10.140.11` (gw `10.10.140.1`)
    - `minio-2` (`proxmox2`): VLAN `10.10.140.12` (gw `10.10.140.1`)
    - `minio-3` (`proxmox3`): VLAN `10.10.140.13` (gw `10.10.140.1`)
  - Stable **LAN VIP** for the Terraform S3 endpoint: `192.168.11.101` (HAProxy+Keepalived on `minio-edge-*`).
  - Deterministic Proxmox UI tags on all CTs: `golden-vN;plane-minio;env-infra;role-edge|role-minio` (Terraform-managed).

- **Ansible playbooks**: `fabric-core/ansible/playbooks/state-backend.yml` (orchestrator)
  - MinIO distributed cluster (`minio-1/2/3`)
  - MinIO edge LB (`minio-edge-1/2`) with HAProxy VIP front door + NAT egress for VLAN140
  - Bucket + terraform user provisioning via `mc` (idempotent, no secrets in Git)

- **Runner bootstrap helper**: `ops/scripts/backend-configure.sh`
  - Creates runner-local credentials and backend CA under `~/.config/samakia-fabric/` (never committed)
  - Installs backend CA into the runner host trust store (strict TLS, no insecure flags)

- **Acceptance suite**: `ops/scripts/minio-accept.sh` (non-interactive)
  - Includes read-only Proxmox API verification of the tag schema (strict TLS, token-only).

### MinIO SDN: Acceptance Coverage

Additional SDN-plane validation is available (read-only):
- `ENV=samakia-minio make minio.sdn.accept`
- Guarantees after PASS (best-effort): SDN primitives exist (zminio/vminio/VLAN140/subnet/gateway VIP), MinIO nodes are VLAN-only and default-route via `10.10.140.1`, and edge gateway VIP/NAT signals are present when edges are reachable.
- Note: if the Proxmox API token cannot read SDN primitives (or the SDN plane is not created yet), this check fails loudly by design.

### MinIO Convergence Guarantees

After `ENV=samakia-minio make minio.converged.accept` returns PASS (and the SDN acceptance prerequisite is PASS), the runner has verified:
- MinIO VIP endpoints are reachable over strict TLS (S3 + console), with no plaintext HTTP on those ports.
- Both edges are running keepalived + haproxy, and VIP ownership is singular and stable.
- Cluster membership signals show 3 nodes and no offline/healing/rebalancing indicators (best-effort).
- Terraform backend bucket/state object presence and basic access posture invariants (no anonymous, terraform user not admin).

### MinIO Quorum Guard (detect-only)

`ENV=samakia-minio make minio.quorum.guard` is a conservative, detect-only gate that blocks unsafe control-plane operations when MinIO is not quorum/HA-safe.

PASS means (best-effort):
- VIP endpoints are reachable over strict TLS and the cluster health endpoint indicates quorum.
- Edge HA sanity holds (exactly one VIP owner; keepalived/haproxy active on both edges).
- Backend reachability signals are present (all 3 MinIO backends reachable via the active edge).
- Admin health signals show no offline/healing/rebalancing indicators (when available via edge `mc admin info`).

It does not guarantee:
- Application-level HA (only platform/backend health signals).
- Absence of latent storage faults beyond what MinIO reports.
- That future failures won’t occur during a long-running apply (it’s a point-in-time safety gate).

### Failure Tolerance Verification

`make minio.failure.sim ENV=samakia-minio EDGE=minio-edge-1` performs a reversible failure simulation by stopping `haproxy` + `keepalived` on one edge and verifying VIP continuity and post-recovery steady state.

PASS means (best-effort):
- VIP stays reachable over strict TLS during the edge outage.
- Exactly one VIP owner exists before, during, and after recovery (no split-brain).
- The faulted edge services are restored to active state.

### Terraform Backend Smoke Test

`ENV=samakia-minio make minio.backend.smoke` performs a real `terraform init` + `terraform plan` against the MinIO S3 backend from an isolated workspace and fails loud if:
- TLS trust is missing (no insecure flags permitted).
- Backend locking is not observed during plan.
- Backend metadata does not match the canonical endpoint and lockfile settings.

It does not guarantee:
- That the backend will remain stable for the full duration of an apply (point-in-time check).
- That state writes will succeed under concurrent lock contention (it validates locking is active, not contention behavior).

### Terraform Backend Bootstrap Invariant

The Terraform remote backend **must not depend on itself** to exist.

Therefore, `ENV=samakia-minio` is bootstrapped with **local state only**:
- `terraform init -backend=false`

Implementation note:
- Make targets bootstrap via a runner-local workspace that copies the env Terraform files excluding `backend.tf` (backend remains in Git) so that `plan/apply` can run before remote S3 exists.
- Bootstrap scripts and script-to-script calls are executed via an explicit repo root (`FABRIC_REPO_ROOT` / `TF_VAR_fabric_repo_root`), never via relative paths or `cwd`.

Only after MinIO is deployed and accepted do we migrate state to the remote S3 backend (explicit step):
- `make minio.state.migrate ENV=samakia-minio`

Guardrails:
- `make tf.backend.init ENV=samakia-minio` fails loudly by design.
- `make tf.plan/tf.apply ENV=samakia-minio` are forbidden; use `minio.tf.plan/minio.tf.apply` (bootstrap-local).

### Failure: Terraform apply prompted for approval (EOF)

Reproduction:

```bash
ENV=samakia-minio make minio.up
```

Root cause:
- `terraform apply` prompts for an interactive `yes` confirmation unless `-auto-approve` is set.
- In non-interactive contexts, this fails with `Error: error asking for approval: EOF`.

Fix:
- Makefile now passes `-auto-approve` automatically when `CI=1` (used by one-command orchestration targets), so `make minio.up` is deterministic and non-interactive.

## DNS Infrastructure — What was implemented

- **Terraform env**: `fabric-core/terraform/envs/samakia-dns/`
  - Proxmox **SDN VLAN plane** ensure step (zonedns/vlandns/VLAN100 + `10.10.100.0/24`, gw VIP `10.10.100.1`) via API-token-only script `ops/scripts/proxmox-sdn-ensure-dns-plane.sh`.
  - Four LXCs with deterministic placement + static IPs:
    - `dns-edge-1` (`proxmox1`): LAN `192.168.11.111`, VLAN `10.10.100.11`
    - `dns-edge-2` (`proxmox2`): LAN `192.168.11.112`, VLAN `10.10.100.12`
    - `dns-auth-1` (`proxmox3`): VLAN `10.10.100.21`
    - `dns-auth-2` (`proxmox2`): VLAN `10.10.100.22`
  - Version-pinned template contract (no “latest”) and immutable rootfs naming.
  - Deterministic Proxmox UI tags on all CTs: `golden-vN;plane-dns;env-infra;role-edge|role-auth` (Terraform-managed).

- **Ansible playbooks**: `fabric-core/ansible/playbooks/dns.yml`, `fabric-core/ansible/playbooks/dns-edge.yml`, `fabric-core/ansible/playbooks/dns-auth.yml`
  - **dns-edge** role: keepalived VRRP (LAN VIP `192.168.11.100` + VLAN GW VIP `10.10.100.1`), dnsdist (VIP-only), unbound, nftables NAT.
  - **dns-auth** role: PowerDNS authoritative master/slave with constrained AXFR/NOTIFY, serving `infra.samakia.net`.

- **Makefile automation** (repo root): `make dns.up ENV=samakia-dns`
  - Runs: runner env checks → Terraform apply → Ansible bootstrap → DNS playbooks → acceptance.

- **Acceptance suite**: `ops/scripts/dns-accept.sh`
  - Non-interactive checks: VIP authoritative answers, recursion, keepalived VIP holder invariants, NAT readiness, pdns replication sanity, Ansible idempotency, best-effort token leak scan.
  - Includes read-only Proxmox API verification of the tag schema (strict TLS, token-only).

### DNS SDN: Acceptance Coverage

Read-only SDN-plane validation is available:
- `ENV=samakia-dns make dns.sdn.accept`
- Guarantees after PASS: SDN primitives exist (zonedns/vlandns/VLAN100/subnet/gateway VIP) and match canonical values.

## DNS Infrastructure — How to run (one command)

1) Ensure runner prerequisites (token env vars + CA trust) are installed per `OPERATIONS.md`.
2) Deploy MinIO backend (required for remote Terraform state):

```bash
make minio.up ENV=samakia-minio
```

3) Deploy DNS (now unblocked by the backend):

```bash
make dns.up ENV=samakia-dns
```

4) Re-run acceptance anytime (non-destructive):

```bash
make minio.accept
make dns.accept
```

## Acceptance status (this workspace)

- `pre-commit run --all-files`: **PASS**
- `bash fabric-ci/scripts/lint.sh`: **PASS**
- `bash fabric-ci/scripts/validate.sh`: **PASS**
- `make minio.up ENV=samakia-minio`: **PASS** (includes SDN apply; strict TLS; token-only)
- `make minio.accept`: **PASS**
- `make minio.quorum.guard ENV=samakia-minio`: **PASS**
- `make minio.backend.smoke ENV=samakia-minio`: **PASS**
- `make minio.state.migrate ENV=samakia-minio`: **PASS** (non-interactive; `-force-copy`)
- `make dns.up ENV=samakia-dns`: **PASS** (bootstraps edges first, then VLAN-only auth via ProxyJump; strict contracts)
- `make dns.accept`: **PASS**

---

# Samakia Fabric – Repository Review (REVIEW.md)

## 1. Executive Summary

Samakia Fabric είναι πλέον ένα production-grade IaaS substrate για Proxmox VE (LXC-first) με ξεκάθαρα security/ops contracts και επιθετικά guardrails. Η αρχιτεκτονική είναι συνεπής με immutability-by-default: versioned golden images, strict TLS (internal CA), API-token-only για Proxmox, 2-phase Ansible (bootstrap → harden), και ξεχωριστό audit/compliance/forensics layer που παράγει signable evidence bundles (GPG signatures, dual-control, TSA tokens) χωρίς auto-remediation.

Τα μεγαλύτερα ρίσκα/κενά δεν είναι “λειτουργικά” αλλά operational sharp edges: SSH trust/known_hosts lifecycle μετά από replace/recreate, DHCP/MAC determinism για σταθερά IPs, και reproducibility guarantees στο image build (docker base / apt drift). Αυτά είναι απολύτως λύσιμα με μικρές, deterministic πολιτικές και επιπλέον “provenance” stamping στο image.

Γενικό verdict: ισχυρό foundation, ήδη αξιοποιήσιμο σε παραγωγή για single-site Proxmox, με σαφή next steps για να γίνει ακόμη πιο deterministic και audit-friendly.

---

## 2. Architectural Assessment

**Strengths**
- Καθαρό layering: Packer (image) → Terraform (lifecycle) → Ansible (policy). Η αλληλουχία και τα συμβόλαια είναι σαφή και enforceable.
- Proxmox-9 safety: αποφυγή forbidden provider, provider pinning, και χρήση API tokens αντί για SSH/root scripts.
- Immutability: versioned rootfs archives (`*-vN.tar.gz`) και storage content type `vztmpl`. Το upload ακολουθεί “immutable rule” (no overwrite).
- GitOps readiness: scripts/runbooks/guardrails σχεδιασμένα για runner-host execution, με deterministic inputs και χωρίς interactive “χαοτικές” εξαρτήσεις στο runtime.

**Operational reality learned**
- Το template “δεν εμφανίζεται” συχνά είναι UI filter issue. Canonical verification: `pvesm list <storage> --content vztmpl`.
- In-place replace/recreate σε CT αλλάζει host key → strict SSH θα μπλοκάρει μέχρι να γίνει controlled known_hosts rotation.

---

## 3. IaC Design Review (Packer / Terraform / Ansible)

### Packer (Golden LXC images)
- Golden LXC image workflow είναι ευθυγραμμισμένο: userless image, root key-only bootstrap, minimal cloud-init.
- Versioning policy υπάρχει και προστατεύει από overwrite.

**Gap**
- Reproducibility/Provenance: αν η βάση είναι docker image + apt updates, υπάρχει drift με τον χρόνο. Προτείνεται:
  - pin docker base digest (όχι μόνο tag),
  - pin apt snapshot/apt proxy snapshot strategy,
  - add image provenance stamp (π.χ. `/etc/samakia-image-version` + build UTC + git SHA).

### Terraform (Proxmox LXC lifecycle)
- Strict TLS χωρίς insecure flags, canonical host CA trust με installer/guardrails.
- SSH keys inject μέσω `ssh_public_keys` για προσωρινό bootstrap access είναι σωστό pattern.
- Inventory fallback μέσω Proxmox API resolve (strict TLS) μειώνει dependency σε DNS/DHCP timing.

**Operational sharp edges**
- Plan/apply δεν θα δείξει “upgrade existing CT to new template” by itself: templates είναι create-time seed. Για νέο golden version σε existing CT απαιτείται `-replace` ή blue/green.

### Ansible (2-phase policy enforcement)
- Phase-1 bootstrap: root-only minimal, CA install στο LXC, operator user + keys + sudo, disable root ssh.
- Phase-2 hardening: runs as `samakia` (become) και είναι LXC-safe (sysctls only when writable, UFW optional, sshd -t validation pre-reload).

**Gap**
- SSH trust model: χρειάζεται explicit operator workflow για known_hosts rotate σε replace/recreate (χωρίς να χαλαρώσει strict checking).

---

## 4. GitOps Model Review

- Guardrails coverage είναι ισχυρό: terraform fmt/validate, ansible-lint, shellcheck, gitleaks, provider pinning enforcement.
- Drift detection/audit reporting ως read-only pipeline είναι σωστό: plan-based drift + ansible check/diff.
- Promotion flow τεκμηριωμένο (image → template → env) και consistent με immutability.

**Gap**
- Καλό θα ήταν να υπάρχει canonical “non-interactive mode” everywhere (inputs μέσω env vars/files) ώστε CI runners να μην μπλοκάρουν.
- Makefile orchestration προσφέρει UX, αλλά πρέπει να αποφεύγει interactive prompts σε CI unless explicitly enabled.

---

## 5. Security Review

**Strengths**
- No insecure TLS: Proxmox API strict TLS trust μέσω internal CA στο host trust store.
- API token only: αφαιρέθηκαν SSH/root scripts προς Proxmox (σωστό).
- Root SSH disabled post-bootstrap. SSH contract verified (operator OK, root FAIL).
- Evidence pipelines:
  - signed compliance snapshots (sha256 manifest + GPG detached signature),
  - dual-control signing (2-person rule),
  - TSA notarization (RFC3161),
  - offline verification pipeline.

**Major risk**
- SSH host key lifecycle: σε replace/recreate αλλάζει host key και strict SSH σταματάει. Αυτό είναι σωστό security posture, αλλά χρειάζεται documented procedure:
  - controlled `ssh-keygen -R <ip|host>`,
  - optional out-of-band fingerprint verification (Proxmox console),
  - never disable strict checking globally.

**Secondary risk**
- Secrets placement: το να μπαίνουν tokens σε `.bashrc` είναι πρακτικά βολικό αλλά risk. Προτείνεται `~/.config/samakia-fabric/env.sh` (chmod 600) και `.bashrc` να κάνει source, όχι inline secret.

---

## 6. High Availability Review

- HA/failure-domains runbook είναι ρεαλιστικό: ξεχωρίζει compute, storage, network partitions και αποφεύγει “HA theater”.
- GameDays / failure simulation framework είναι production-minded: safety gates, abort criteria, roles (conductor/observer/comms), verification + rollback, evidence capture.

**Gap**
- Single Proxmox node: HA είναι πρακτικά “operational resilience” όχι true HA. Τα runbooks πρέπει να συνεχίσουν να το λένε ωμά (και ήδη το κάνουν).

---

## 7. Operational Readiness

**Strengths**
- Break-glass / recovery runbooks: SSH lockout, firewall lockout, sshd repair, key restore via console, safe rerun rules (bootstrap vs harden).
- Pre-release readiness audit framework: Go/No-Go gate, acceptance criteria, signable readiness packet scaffolding.
- Legal hold/retention automation: label-only packs independent from evidence manifests, dual-control markers, release workflow.
- Shared control-plane services: deterministic SDN plane + VIP endpoints (NTP/Vault/observability) with read-only acceptance gates.

**Operational sharp edges**
- DHCP determinism: σε in-place replace αλλάζει MAC → αλλάζει IP. Αυτό απαιτεί:
  - DHCP reservations by MAC, ή
  - fixed hwaddr/MAC management via IaC (όπου υποστηρίζεται),
  - explicit cutover strategy (DNS/IP).

---

## 8. Documentation Quality

- Docs-first approach είναι ισχυρό asset: promotion, break-glass, compliance audits, key custody, evidence notarization, app compliance overlay, forensics, HA simulation, readiness.
- Τα runbooks είναι “03:00-safe”: βήματα, safety gates, no root SSH assumption.
- Clear contracts: “no insecure TLS”, “API token only”, “root SSH disabled”, “no auto-remediation in drift”.

**Gap**
- Να προστεθεί μικρό operator tip section σε relevant runbooks:
  - canonical template verification via `pvesm list ... --content vztmpl`,
  - known_hosts rotate step after replace/recreate,
  - DHCP/MAC determinism recommendation.

---

## 9. AI-Operability Assessment

Το repo είναι AI-operable με ασφάλεια, επειδή:
- Υπάρχουν guardrails που αποτρέπουν risky changes (provider pinning, gitleaks, shellcheck, ansible-lint).
- Τα audit/compliance/forensics scripts είναι read-only by default, χωρίς auto-remediation.
- Τα runbooks έχουν explicit contracts και “do not relax security”.

**Risk**
- Interactive prompts (Terraform vars, selection menus) μπορεί να μπερδέψουν agents. Πρέπει να υπάρχει consistent non-interactive mode + clear env var contract για runners.

---

## 10. Risks and Gaps

1) **Reproducibility risk στο image build** (docker base/apt drift) → μειώνει audit confidence.
2) **SSH known_hosts lifecycle** μετά από replace/recreate → operational friction, χρειάζεται canonical procedure (όχι disable strict).
3) **DHCP/MAC determinism** → IP changes σε replace, impact σε automation/monitoring/ops.
4) **Dev/staging parity** → χωρίς πλήρη staging env, promotion έχει λιγότερα safety nets.
5) **“Template upgrade” misconception** → απαιτεί explicit replace/blue-green, δεν είναι in-place upgrade feature.

---

## 11. Recommendations (Short / Medium / Long term)

### Short-term (next 1–2 iterations)
- Add image provenance stamp (`/etc/samakia-image-version`, build UTC, git SHA).
- Document known_hosts rotate workflow (strict) ως explicit step μετά από replace.
- Make DHCP reservations by MAC canonical for key CTs (or pin MAC in IaC if feasible).
- Add “pvesm list” verification snippets σε operations docs.

### Medium-term
- Improve image reproducibility: pin base image digest + apt snapshot strategy.
- Add a minimal staging env that mirrors prod guardrails and runs promotion end-to-end.
- Expand “non-interactive runner mode” for all ops commands (CI-safe).

### Long-term
- True HA requires multi-node cluster + storage/network architecture. Keep HA design honest and operationally tested via GameDays.
- Consider formalizing evidence chain-of-custody into a single “audit packet” standard across substrate/app/forensics.

---

## 12. Final Verdict

Samakia Fabric είναι ένα σοβαρό, production-ready substrate για Proxmox LXC IaaS με unusually strong compliance/evidence/forensics capabilities και σωστό security posture (strict TLS, API tokens, root SSH disabled). Ο σχεδιασμός είναι συνεπής και τα guardrails είναι ουσιαστικά.

Το project είναι έτοιμο για παραγωγή σε single-site Proxmox, με την προϋπόθεση ότι θα υιοθετηθούν ως standard τα operational procedures για SSH trust rotation και DHCP determinism, και θα ενισχυθεί η reproducibility/provenance του golden image build.

Verdict: **GO for production foundation**, με τα Short-term items ως required hardening για να μειωθούν τα day-0/day-2 sharp edges.

## Phase 2.1 Acceptance Note

Phase 2.1 (Shared Control Plane Services) has been accepted and locked via `acceptance/PHASE2_1_ACCEPTED.md`.
No regressions were introduced to Phase 2 DNS/MinIO contracts or acceptance gates.

## Phase 2.2 Correctness Note

Phase 2.2 hardens shared control-plane correctness beyond reachability:
Loki ingestion is verified, and systemd readiness/restart policies are enforced.
Acceptance remains read-only, strict TLS, and IP-only (no DNS dependency).

Phase 2.2 (Control Plane Correctness & Invariants) has been accepted and locked via `acceptance/PHASE2_2_ACCEPTED.md`.

## Phase Closure Summary

Phase 2 (Networking & Platform Primitives) is completed and locked.
Phase 2.1 (Shared Control Plane Services) is completed and locked.
Phase 2.2 (Control Plane Correctness & Invariants) is completed and locked.
No regressions were introduced.
Phase 3 entry is READY.

## Phase 3 Entry Status

Phase 3 entry is **READY** based on live readiness verification (see `acceptance/PHASE3_ENTRY_CHECKLIST.md`).

## Phase 3 Part 1 — HA Semantics

Phase 3 Part 1 establishes deterministic HA semantics and failure-domain validation:

- HA tiers and failure-domain model defined in `OPERATIONS_HA_SEMANTICS.md`.
- Placement policy enforced by `fabric-core/ha/placement-policy.yml` and `make ha.placement.validate`.
- Proxmox HA audit guardrails via `make ha.proxmox.audit`.
- Read-only evidence snapshots via `make ha.evidence.snapshot`.
- Acceptance marker: `acceptance/PHASE3_PART1_ACCEPTED.md`.

## Phase 3 Part 2 — GameDay Framework

Phase 3 Part 2 adds a safe GameDay workflow and dry-run acceptance:

- GameDay precheck + evidence snapshot + postcheck tooling under `ops/scripts/gameday/`.
- VIP failover and service restart simulations are guarded and dry-run by default.
- Acceptance gate: `make phase3.part2.accept`.

## Phase 3 Part 3 — HA Enforcement

Phase 3 Part 3 turns HA semantics into **hard enforcement**:

- Placement policy is enforced before Terraform plan/apply (`make ha.enforce.check`).
- Proxmox HA declarations are audited in enforcement mode (`--enforce`).
- Explicit overrides require `HA_OVERRIDE=1` and `HA_OVERRIDE_REASON`.
- Acceptance gate: `make phase3.part3.accept`.

## Phase 4 — GitOps & CI Workflows

Phase 4 integrates infrastructure lifecycle with **read-only-first CI** and **policy gates**:

- PR validation runs `policy.check`, pre-commit, lint, validate, and HA enforcement.
- PR plan workflows produce **evidence packets** with manifests (no secrets).
- Non-prod apply is manual and gated (explicit confirmation phrase; dev/staging only).
- Drift, app compliance, and release readiness packets are produced as artifacts.

Phase 2.x and Phase 3 behavior remain unchanged; Phase 4 adds governance and evidence automation only.

---

## Phase 5 — Advanced Security & Compliance

Phase 5 strengthens security posture while preserving offline operability:
- Offline-first secrets interface (encrypted file), with optional Vault read-only mode.
- Guarded SSH key rotation workflows (operator + break-glass) with evidence packets.
- Default-off firewall profiles with explicit apply guards and read-only validation.
- Compliance profile evaluation mapped to the control catalog (baseline/hardened).

Phase 2.x, Phase 3 enforcement, and Phase 4 CI gates remain unchanged; Phase 5 adds policy-guarded security workflows only.

---

## Phase 6 — Platform Consumers (Parts 1–3)

Phase 6 Part 1 turns consumer contracts into enforced, testable mechanics (no deployments):
- Contract validation (schema + semantics) for `ready`/`enabled` variants.
- HA readiness checks and disaster wiring validation (read-only).
- Consumer readiness evidence packets under `evidence/consumers/`.
- Acceptance marker: `acceptance/PHASE6_PART1_ACCEPTED.md`.

Phase 6 Part 2 adds safe GameDay wiring and bundle outputs (dry-run only):
- Consumer GameDay mapping validation + dry-run execution (no mutation).
- Consumer bundles for ports, firewall intents, storage, and observability labels.
- Acceptance marker: `acceptance/PHASE6_PART2_ACCEPTED.md`.

Phase 6 Part 3 enables **controlled execute mode** for SAFE GameDays:
- Execute allowlists (dev/staging only), maintenance windows, and operator reason guards.
- Optional signing of execute-mode evidence packets (no secrets).
- Acceptance marker: `acceptance/PHASE6_PART3_ACCEPTED.md`.

---

## Phase 7 — AI Operations Safety

Phase 7 adds bounded AI participation with explicit guardrails:
- AI operations policy and ADR (read-only default, guarded remediation).
- Plan review packets from Terraform plan artifacts (read-only).
- Safe-run allowlist with evidence wrapper packets.
- Phase 7 acceptance marker: `acceptance/PHASE7_ACCEPTED.md`.

Phase 2.x, Phase 3 enforcement, Phase 4 CI gates, Phase 5 security posture, and Phase 6 consumer model remain unchanged.

---

## Phase 8 — VM Golden Image Contracts (Design)

Phase 8 introduces VM golden image contracts as immutable artifacts (design-only):
- ADR-0025 locks artifact-first scope (storage path + sha256; no VM lifecycle).
- VM image contract schema and example contracts (Ubuntu 24.04, Debian 12).
- Entry checklist and acceptance plan for design validation (no builds).
- Docs skeleton under `docs/images/` for operator guidance.

Phase 8 Part 1 adds a validate-only pipeline for VM artifacts (no Proxmox, no VM provisioning):
- Packer templates + Ansible hardening playbook for Ubuntu 24.04 and Debian 12.
- Offline qcow2 validators (cloud-init, SSH posture, pkg manifest, build metadata).
- Evidence packets for build/validate under `evidence/images/vm/`.
- Acceptance marker: `acceptance/PHASE8_PART1_ACCEPTED.md` (validate-only).

Phase 8 Part 1.1 makes the pipeline operator-repeatable locally (guarded builds):
- Local runbook: `docs/images/local-build-and-validate.md`.
- Safe wrapper: `ops/images/vm/local-run.sh` with explicit build guards.
- Evidence verification helper: `ops/images/vm/evidence/verify-evidence.sh`.
- Acceptance marker: `acceptance/PHASE8_PART1_1_ACCEPTED.md`.

Phase 8 Part 1.2 adds an optional pinned toolchain container:
- Container definition: `tools/image-toolchain/`.
- Wrapper: `ops/images/vm/toolchain-run.sh` (opt-in, guarded).
- Acceptance marker: `acceptance/PHASE8_PART1_2_ACCEPTED.md`.

Phase 8 Part 2 adds guarded Proxmox template registration:
- Token-only API registration with strict TLS and allowlisted environments.
- Deterministic evidence packets for register/verify under `evidence/images/vm/`.
- Acceptance marker: `acceptance/PHASE8_PART2_ACCEPTED.md` (read-only acceptance).

---

## Phase 9 — Operator UX & Doc Governance

Phase 9 makes operator UX a product surface:
- Canonical operator cookbook: `docs/operator/cookbook.md`.
- Safety model + evidence guidance under `docs/operator/`.
- Consumer catalog + guided flows under `docs/consumers/`.
- Anti-drift doc checks (`make docs.operator.check`) wired into PR validation.
- Acceptance marker: `acceptance/PHASE9_ACCEPTED.md`.

---

## Phase 10 — Tenant = Project Binding (Design)

Phase 10 introduces design-only tenant contracts:
- ADR-0027 locking tenant = project binding model.
- Tenant schemas, templates, and examples under `contracts/tenants/`.
- Tenant docs skeleton under `docs/tenants/`.
- Validation gates: `make tenants.validate` and `make phase10.entry.check`.
Phase 10 Part 1 adds non-destructive enforcement and evidence:
- Policy/quotas and consumer binding validation (`make tenants.validate`).
- Deterministic evidence packets under `evidence/tenants/...`.
- Acceptance marker: `acceptance/PHASE10_PART1_ACCEPTED.md`.
Phase 10 Part 2 adds guarded execute mode and DR harness:
- ADR-0028 locking execute-mode guardrails (offline-first, no CI execute).
- Execute policy allowlists + guarded plan/apply (`make tenants.plan`, `make tenants.apply`).
- Offline-first credential issuance under `ops/tenants/creds/`.
- Tenant DR dry-run/execute harness (`make tenants.dr.run`).
No infrastructure is deployed in Phase 10.

## Phase 11 — Tenant-Scoped Substrate Executors (Design)

Phase 11 formalizes **enabled** substrate executor contracts for tenant-ready
stateful primitives, without any execution:

- ADR-0029 locking the contract-first executor model (design-only).
- Substrate DR taxonomy under `contracts/substrate/dr-testcases.yml`.
- Enabled executor schemas + templates for substrate consumers.
- Validation gate: `make substrate.contracts.validate`.

No infrastructure is deployed in Phase 11. The deliverable is contract
consistency, DR taxonomy enforcement, and read-only validation.

## Phase 11 Part 1 — Plan-Only Executors

Phase 11 Part 1 makes the design actionable without mutation:

- Plan-only executor scaffold for Postgres/MariaDB/RabbitMQ/Dragonfly/Qdrant.
- DR dry-run harness mapped to the shared DR taxonomy.
- Deterministic evidence packets under `evidence/tenants/<tenant>/<UTC>/`.
- Read-only Make targets: `substrate.plan`, `substrate.dr.dryrun`, `substrate.doctor`.

This is still **non-destructive**: no apply paths, no secrets issuance, and no
infrastructure mutation.

## Phase 11 Part 2 — Guarded Execution

Phase 11 Part 2 introduces **opt-in** execution for enabled tenant bindings with strict guards:

- Execute policy allowlists for env/tenant/provider/variant; prod requires change window + signing.
- Guarded apply/verify/DR execute scripts per provider.
- Deterministic, redacted evidence packets under `evidence/tenants/<tenant>/<UTC>/`.

CI remains read-only: plan, dry-run, and verify only.

## Phase 11 Part 3 — Capacity Guardrails

Phase 11 Part 3 adds tenant-scale safety controls for noisy-neighbor and SLO
correctness without changing execution semantics:

- Tenant `capacity.yml` contracts with schema/template/examples.
- Capacity guardrails evaluated before apply/DR execute (contract-only in CI).
- SLO/failure semantics validation for single vs cluster variants.
- Deterministic capacity evidence under `evidence/tenants/<tenant>/<UTC>/substrate-capacity/`.

Acceptance remains read-only and CI-safe; no apply or DR execute is triggered.

## Phase 11 Part 4 — Runtime Observability & Drift Detection

Phase 11 Part 4 adds read-only runtime observation and drift comparison for
enabled contracts, without any remediation:

- Read-only observe/compare engines for substrate consumers.
- Deterministic evidence packets under `evidence/tenants/<tenant>/<UTC>/substrate-observe/`.
- CI gates for `substrate.observe` and `substrate.observe.compare`.

Drift is reported as PASS/WARN/FAIL but never auto-remediated; all outputs are
redacted and evidence is gitignored.

## Phase 11 Part 5 — Alert Routing Defaults (Evidence-Only)

Phase 11 Part 5 defines environment-aligned, conservative drift alert routing
defaults:

- Explicit tenant allowlist and provider filters (no wildcards).
- Evidence-only emission with local packets; all sinks disabled by default.
- Quiet hours and maintenance window requirements for production.

No remediation or external delivery is enabled unless explicitly configured.

## Phase 11 Hardening Gate — Pre-Exposure

The pre-exposure hardening gate consolidates contract integrity, capacity
guardrails, and read-only observability checks into a single **PASS/FAIL**
checkpoint before Phase 12 exposure. It is deliberately non-destructive:
reachability is best-effort and failures are reported without remediation.
This reduces exposure risk by ensuring all governance and validation layers
are intact before any workload-facing routing is enabled.

The hardening checklist is machine-verifiable: `hardening/checklist.json` is
the source of truth, validated in CI and rendered into operator-facing
markdown.

## Phase 12 Part 1 — Tenant Bindings (Contract-Only)

Phase 12 Part 1 introduces tenant binding contracts that map workloads to
enabled substrate endpoints without provisioning or secrets issuance:

- Contract schema + templates under `contracts/bindings/`.
- Validation + safety gates (`make bindings.validate`).
- Read-only connection manifest rendering (`make bindings.render`).
- Guarded apply entrypoint with evidence output (opt-in; never in CI).

Bindings are contract-only and deterministic; manifests are redacted and
evidence remains gitignored.

## Phase 12 Part 2 — Binding Secrets (Operator-Controlled)

Phase 12 Part 2 adds guarded secret materialization and rotation hooks for
binding contracts without introducing self-service or CI execution:

- Secret shapes (keys only) under `contracts/secrets/shapes/`.
- Materialize/inspect hooks (dry-run by default) via `ops/bindings/secrets/`.
- Rotation plan/dry-run/execute hooks (guarded) via `ops/bindings/rotate/`.
- Policy gates enforce no inline secrets, allowlisted backends, and prod
  change windows + signing.

Secret values remain local-only; evidence is redacted and gitignored.

## Phase 12 Part 3 — Workload-Side Binding Verification

Phase 12 Part 3 adds read-only verification of workload connectivity using
rendered binding manifests:

- Offline verification produces deterministic evidence under `evidence/bindings-verify/`.
- Live verification is guarded (`VERIFY_MODE=live`, `VERIFY_LIVE=1`) and blocked in CI.
- Probes are read-only and never mutate workloads or substrate services.

Verification is conservative: unreachable endpoints are marked **unknown** rather
than failing the contract, preserving CI safety.

## Phase 12 Part 4 — Optional Proposal Workflow

Phase 12 Part 4 introduces an optional proposal workflow that enables tenants
to **request** binding or capacity changes without any autonomous apply:

- Proposal schema + examples under `contracts/proposals/` and `examples/proposals/`.
- Intake, validation, review, and decision tooling under `ops/proposals/`.
- Explicit approval + signing requirements (prod approvals signed).
- Apply path remains operator-controlled and guarded; no CI execution.

Proposals are immutable inputs; evidence bundles and decisions are deterministic
and gitignored.
