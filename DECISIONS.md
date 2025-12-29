# Architecture Decision Records (ADR) — Samakia Fabric

This document records **key architectural and operational decisions**
made in the Samakia Fabric project.

The purpose of this file is:

- Preserve design intent
- Explain trade-offs
- Prevent accidental regressions
- Enable informed future changes

This document is authoritative.

---

## ADR-0001 — Infrastructure as Code as the Primary Control Plane

**Status:** Accepted
**Date:** 2025-12-26

### Decision

All infrastructure must be managed via **Infrastructure as Code (IaC)**.
Manual changes are considered temporary and must be reconciled back into code.

### Rationale

- Prevents configuration drift
- Enables reproducibility
- Enables safe automation and AI agents
- Improves auditability

### Consequences

- Manual fixes are discouraged
- Emergency changes must be documented and codified afterward

---

## ADR-0002 — Proxmox as the Primary Virtualization Platform

**Status:** Accepted
**Date:** 2025-12-26

### Decision

Samakia Fabric is built around **Proxmox VE** as the base virtualization layer.

### Rationale

- Strong LXC support
- Open ecosystem
- On-prem friendly
- HA, SDN, and storage integration

### Consequences

- Terraform provider limitations are accepted
- Design avoids unsupported or unstable Proxmox API features

---

## ADR-0003 — LXC Preferred Over VMs

**Status:** Accepted
**Date:** 2025-12-26

### Decision

**LXC containers** are the default compute unit.
VMs are used only when explicitly required.

### Rationale

- Lower resource overhead
- Faster provisioning
- Better density
- Sufficient isolation for most workloads

### Consequences

- Containers are treated as disposable
- Kernel is shared and must be trusted
- Feature flags must be immutable

---

## ADR-0004 — Golden Images Must Be Generic

**Status:** Accepted
**Date:** 2025-12-26

### Decision

Golden images must:
- Contain no users
- Contain no SSH keys
- Contain no environment-specific configuration

### Rationale

- Reusability
- Security
- Clean separation of concerns

### Consequences

- All customization happens post-provisioning
- Ansible is responsible for user and policy configuration

---

## ADR-0005 — Terraform Is Not a Provisioner

**Status:** Accepted
**Date:** 2025-12-26

### Decision

Terraform is used **only** for infrastructure lifecycle management.
It must not perform OS or application provisioning.

### Rationale

- Clear responsibility boundaries
- Predictable plans
- Reduced blast radius

### Consequences

- No `remote-exec`
- No `file` provisioners
- Provisioning belongs to Ansible

---

## ADR-0006 — Ansible for OS Configuration and Policy

**Status:** Accepted
**Date:** 2025-12-26

### Decision

Ansible is responsible for:
- User management
- SSH configuration
- sudo policy
- OS hardening

### Rationale

- Idempotent configuration
- Human-readable intent
- Mature ecosystem

### Consequences

- Ansible must remain idempotent
- No infrastructure creation logic allowed

---

## ADR-0007 — Delegated Proxmox User for Automation

**Status:** Accepted
**Date:** 2025-12-26

### Decision

Automation (Terraform) must run using a **delegated Proxmox user**,
never `root@pam`.

### Rationale

- Principle of least privilege
- Reduced blast radius
- Auditable access

### Consequences

- Some Proxmox features are intentionally unavailable
- Terraform must avoid forbidden mutations (e.g. feature flags)

---

## ADR-0008 — Immutable LXC Feature Flags

**Status:** Accepted
**Date:** 2025-12-27

### Decision

LXC feature flags (nesting, keyctl, etc.) are immutable after creation.

### Rationale

- Proxmox API restrictions
- Permission limitations
- Stability

### Consequences

- Feature flags must be decided at creation time
- Terraform ignores feature drift

---

## ADR-0009 — Rebuild Over Repair

**Status:** Accepted
**Date:** 2025-12-27

### Decision

Broken containers should be **destroyed and recreated**, not repaired in place.

### Rationale

- Faster recovery
- Less entropy
- Predictable state

### Consequences

- Containers are treated as cattle
- Persistent data must live outside containers

---

## ADR-0010 — SSH Key-Only Access

**Status:** Accepted
**Date:** 2025-12-27

### Decision

SSH access is **key-only**.
Password authentication is forbidden.

### Rationale

- Stronger security
- Automation-friendly
- Auditable access

### Consequences

- SSH keys must be managed carefully
- Bootstrap flow must be respected

---

## ADR-0011 — Documentation as a First-Class Artifact

**Status:** Accepted
**Date:** 2025-12-27

### Decision

Documentation is treated as a **core part of the system**, not an afterthought.

### Rationale

- Enables safe collaboration
- Enables AI agents
- Reduces operational risk

### Consequences

- Changes require documentation updates
- Missing documentation is considered a defect

---

## ADR-0012 — AI Agents Are First-Class Contributors

**Status:** Accepted
**Date:** 2025-12-27

### Decision

The project is designed to be operated and extended by **AI agents**
following explicit rules (`AGENTS.md`).

### Rationale

- Future-proof collaboration
- Deterministic automation
- Reduced human error

### Consequences

- Rules must be explicit
- Ambiguity is a bug




## ADR-0013: DNS Edge Nodes are VLAN Gateways + Controlled Ingress (Single LAN VIP)

**Status:** Accepted
**Date:** 2025-12-28

### Context
We operate multiple VLAN-scoped LXC networks where:
- VLAN workloads must have reliable internet egress.
- A single stable DNS endpoint is required for all VMs and LXCs.
- LAN exposure of VLAN services must be strictly controlled and port-scoped.
- HA is required across Proxmox nodes.

The public domain is `samakia.net`. The internal authoritative zone is `infra.samakia.net`.

###  Decision
We will deploy two `dns-edge` nodes (`dns-edge-1`, `dns-edge-2`) as the **only** ingress/egress gateways for VLAN-scoped LXC networks and as the **single DNS endpoint** for all infrastructure.

### DNS VIP (LAN)
- The canonical DNS endpoint for **all** VMs and LXCs is:
  - `192.168.11.100` (LAN VIP)
- `dns-edge-*` hold this VIP using Keepalived (VRRP).
- DNS must answer on UDP/TCP 53 on the VIP.
- `dns-edge-*` provide recursion via Unbound and forward `infra.samakia.net` to PowerDNS Authoritative.

### VLAN Gateways (Egress)
- Every VLAN has a **gateway VIP** hosted on `dns-edge-*` using VRRP on the corresponding VLAN interface/subinterface.
- All VLAN LXCs must use the VLAN gateway VIP as their default gateway.
- `dns-edge-*` must provide NAT/SNAT for VLAN subnets to reach the internet via the LAN uplink.
- Inbound from LAN to VLAN is denied by default.

### Controlled Ingress (LAN -> VLAN via specific ports)
- VLAN services are exposed to LAN **only** via `dns-edge-*` and **only** on explicitly approved ports.
- TCP ingress is implemented via HAProxy listeners on the LAN VIP (or dedicated LAN VIPs if required).
- UDP ingress is implemented via explicitly scoped nftables DNAT rules (or HAProxy where supported).
- No direct LAN routing to VLAN services is allowed (no “flat” access).

### Authoritative DNS
- PowerDNS Authoritative runs on VLAN-only nodes (`dns-auth-1` master, `dns-auth-2` slave).
- The internal zone is `infra.samakia.net`.
- `dns-edge-*` forward `infra.samakia.net` to `dns-auth-*` and recurse everything else via Unbound.

### VLAN100 is the canonical DNS/control-plane VLAN: 10.10.100.0/24
### Gateway VIP for VLAN100: 10.10.100.1 (VRRP on dns-edge nodes)

### Proxmox SDN (IaC-managed prerequisite)
- SDN zone: `zonedns`
- SDN vnet: `vlandns` (VLAN tag `100`)
- SDN subnet: `10.10.100.0/24` with gateway VIP `10.10.100.1`

### Minimum authoritative records (infra.samakia.net)
At minimum, the authoritative zone must contain:
- `dns.infra.samakia.net` → `192.168.11.100` (DNS VIP)
- `dns-edge-1.infra.samakia.net` → `10.10.100.11`
- `dns-edge-2.infra.samakia.net` → `10.10.100.12`
- `dns-auth-1.infra.samakia.net` → `10.10.100.21` (master)
- `dns-auth-2.infra.samakia.net` → `10.10.100.22` (slave)

## Consequences
- All clients use a single LAN IP for DNS, simplifying DHCP and runner configuration.
- VLAN internet access is deterministic and HA-capable via VRRP gateway VIPs.
- Exposure of VLAN services is centralized, auditable, and port-scoped.
- Subsequent stateful services (e.g., MinIO, Vault, Postgres, etc.) must be deployed behind this gateway/ingress pattern.

## ADR-0014 — Terraform Remote State Backend: MinIO HA Behind Dedicated Stateful Edges

### Decision

Terraform state is stored in a remote S3-compatible backend implemented as:
- **MinIO distributed cluster** on a dedicated **stateful VLAN**
- A dedicated **edge pair** (`minio-edge-*`) providing:
  - a single stable **LAN VIP** for the S3 endpoint
  - a **VLAN gateway VIP** for the stateful VLAN
  - HAProxy as the S3/console front door
  - NAT egress for stateful VLAN services

### Rationale

- Terraform state is a platform control-plane dependency and must be:
  - shared (not local-only)
  - lockable (`use_lockfile = true`)
  - recoverable
  - reachable without DNS dependency (VIP IP is sufficient)
- HAProxy + Keepalived is a boring, deterministic HA front door that fits the existing edge/gateway contract.
- MinIO provides a self-hosted S3 API compatible with Terraform backends without introducing cloud services.

### Topology (canonical)

Stateful VLAN plane:
- VLAN: `140`
- SDN zone: `zminio`
- SDN vnet: `vminio` (tag `140`)
- Subnet: `10.10.140.0/24`
- Gateway VIP (VRRP): `10.10.140.1` (on `minio-edge-*`)

MinIO cluster nodes (VLAN-only IPs):
- `minio-1` → `10.10.140.11` (proxmox1)
- `minio-2` → `10.10.140.12` (proxmox2)
- `minio-3` → `10.10.140.13` (proxmox3)

MinIO edge / front door:
- `minio-edge-1` dual-homed (LAN + VLAN140)
- `minio-edge-2` dual-homed (LAN + VLAN140)
- S3/console LAN VIP: `192.168.11.101`
  - S3: `https://192.168.11.101:9000`
  - Console: `https://192.168.11.101:9001`

Authoritative DNS (infra.samakia.net) records must include:
- `minio.infra.samakia.net` → `192.168.11.101`
- `minio-console.infra.samakia.net` → `192.168.11.101`

### Security and contracts

- Strict TLS:
  - HAProxy terminates TLS with a certificate issued by the backend internal CA
  - The backend CA is installed in the runner host trust store (no insecure flags)
- Proxmox access remains API token only (no node SSH/SCP).
- No secrets are committed to Git; runner-local credentials and CA material live under `~/.config/samakia-fabric/`.
- Terraform locking uses S3 lockfiles (no DynamoDB).

## Non-negotiable Rules
- This decision is canonical. All subsequent implementations MUST follow it.
- No additional DNS endpoints on LAN are permitted.
- No direct LAN-to-VLAN service access is permitted outside explicitly declared ports on `dns-edge-*`.

## ADR-0015 — Golden Image Versioning: Artifact-Driven Monotonic Versions

**Status:** Accepted
**Date:** 2025-12-29

### Decision

Golden image versions are derived from **existing artifacts on disk**, not from manual edits in repo files.

- Artifact naming is canonical and immutable:
  - `ubuntu-24.04-lxc-rootfs-v<N>.tar.gz`
- The next version is computed as:
  - `N = max(existing artifacts) + 1` (or `1` if none exist)
- Builds MUST refuse to overwrite an existing versioned artifact.

Version bumps MUST NOT require editing:
- Packer HCL files
- Makefile variables
- docs/README per version

### Rationale

- Keeps image build promotion **boring and deterministic**.
- Prevents accidental overwrites of a supposedly immutable artifact.
- Aligns with GitOps:
  - artifacts are immutable
  - environment pins are Git changes
  - rollbacks are Git reversions to a previous pinned version

### Operational contract (canonical)

Build (auto-bump):
- `make image.build-next` (computes `vN`, builds, prints absolute artifact path)

Upload (API-token workflow; refuses overwrite):
- `make image.upload IMAGE=<artifact-path>`
- or `bash fabric-core/packer/lxc/scripts/upload-lxc-template-via-api.sh <artifact-path>`

Promote (Git change only):
- `make image.promote IMAGE=<artifact-path> DST_ENV=<env>`

## ADR-0016 — Proxmox UI Tagging: Deterministic key/value tags (Proxmox-safe) for golden image + planes

**Status:** Accepted
**Date:** 2025-12-29

### Decision

All Terraform-managed LXCs MUST have deterministic Proxmox UI tags, set by Terraform as the source of truth.

Canonical schema (semicolon-separated; Proxmox tag charset-safe):

- `golden-vN;plane-<plane>;env-<env>;role-<role>`

Rules:

- `golden-vN` is derived from the immutable template artifact name (`*-v<N>.tar.gz`).
- `plane` expresses the infrastructure plane (`dns`, `minio`, `monitoring`, ...).
- `env` is one of:
  - `dev|staging|prod` for standard environments
  - `infra` for dedicated infra planes (`samakia-dns`, `samakia-minio`)
- `role` is workload-specific but must be short and stable (`edge`, `auth`, `minio`, `mon`, ...).
- `-` is used as a key/value separator because Proxmox tags do not allow `=` in tag values.
- Tags MUST NOT contain secrets, IPs, or spaces.
- Tags MUST be semicolon-separated; commas are forbidden.

### Rationale

- Makes the golden image version visible on every running CT in Proxmox UI (filtering, audits, incident response).
- Prevents tag drift from manual UI edits (Terraform remains authoritative).
- Provides compact, stable metadata usable across runbooks and operator workflows.

### Consequences

- Manual tag edits in Proxmox UI are treated as drift and will be corrected by Terraform on the next apply.
- Unversioned templates (missing `-vN.tar.gz`) are invalid and must fail loudly (immutability contract).

## ADR-0017 — Terraform Backend Cannot Depend on Itself (MinIO bootstrap invariant)

**Status:** Accepted
**Date:** 2025-12-29

### Decision

The Terraform remote backend MUST NOT depend on itself to exist.

Therefore, the backend-providing environment `ENV=samakia-minio` MUST always bootstrap with **local state**:

- `terraform init -backend=false`

Implementation note:
- Makefile targets bootstrap from a runner-local workspace that copies the env Terraform files excluding `backend.tf` (backend remains in Git), because Terraform cannot `plan/apply` with an uninitialized `backend "s3"` configuration.
- Terraform `local-exec` must not rely on the runner's working directory; the repo root is injected as `TF_VAR_fabric_repo_root` and local-exec references scripts via `${var.fabric_repo_root}/ops/scripts/...`.
- Operational scripts must not rely on `cwd` or relative script paths; script-to-script calls use `"$FABRIC_REPO_ROOT/..."`, and scripts fail loudly if `FABRIC_REPO_ROOT` is unset.

Only AFTER MinIO is deployed and accepted may its Terraform state be migrated to the remote S3 backend.

Operational contract (canonical):

- Bootstrap-local (allowed):
  - `make minio.tf.plan ENV=samakia-minio` (runs `terraform init -backend=false`)
  - `make minio.tf.apply ENV=samakia-minio` (runs `terraform init -backend=false`)
- Migration (explicit, one-time):
  - `make minio.state.migrate ENV=samakia-minio` (migrates local state to remote backend)

### Guardrails

- `make tf.backend.init ENV=samakia-minio` MUST fail loudly.
- `make tf.plan/tf.apply ENV=samakia-minio` MUST fail loudly (use `minio.tf.*`).

### Rationale

- Prevents the expected bootstrap failure: “Backend initialization required”.
- Keeps the bootstrap deterministic and CI-safe without introducing manual steps or insecure flags.





---

## How to Add a New Decision

1. Add a new ADR entry
2. Use the next incremental ID
3. Clearly state:
   - Decision
   - Rationale
   - Consequences
4. Reference related ADRs if applicable

Unrecorded decisions are considered invalid.

---

## Final Note

If you find yourself asking:
> “Why was this done this way?”

The answer **must exist in this file**.

If it doesn’t:
- Add it.
- Or reconsider the change.
