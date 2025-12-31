# HA Semantics & Failure Domains — Phase 3 Part 1

This document defines **how Samakia Fabric interprets "HA"**, how workloads are
classified, and how failure domains are enforced. It complements:

- `OPERATIONS_HA_FAILURE_DOMAINS.md`
- `OPERATIONS_HA_FAILURE_SIMULATION.md`

## 1) HA Tiers (Workload Classification)

HA tiers are **explicit** and **deterministic**. Each workload is assigned a tier
in `fabric-core/ha/placement-policy.yml` and validated via `make ha.placement.validate`.

### Tier 0 — Control-plane critical (VIP holders)
- Examples: `dns-edge-*`, `minio-edge-*`, `ntp-*` (shared edges)
- Failure semantics: VIP failover expected within seconds
- Placement rule: **anti-affinity required** across Proxmox nodes
- HA mechanism: **Keepalived VIP**, not Proxmox HA

### Tier 1 — Stateful core services
- Examples: `minio-*`, `vault-*`, `dns-auth-*`, `obs-*`
- Failure semantics: service-level HA across nodes where possible
- Placement rule: **anti-affinity required** unless explicitly documented
- HA mechanism: application-level or service-level HA (not Proxmox HA by default)

### Tier 2 — Non-critical tooling
- Examples: `monitoring-*`
- Failure semantics: downtime acceptable; best-effort placement
- Placement rule: anti-affinity optional
- HA mechanism: none unless explicitly documented

## 2) Failure Domains

The **primary failure domain is the Proxmox node**. Optional rack/zone labels
may be added later, but are **not required** for Phase 3 Part 1.

Failure domain inventory is defined in:

- `fabric-core/ha/placement-policy.yml`

## 3) HA Semantics (Proxmox HA vs VIP HA)

Samakia Fabric distinguishes between:

- **VIP HA (Keepalived)**
  - Provides fast failover for VIP endpoints
  - Used by edge pairs (DNS, MinIO, Shared services)
  - Does **not** imply Proxmox HA configuration

- **Proxmox HA**
  - Explicit Proxmox HA resource management
  - Not enabled by default
  - If used, must be declared in placement policy and audited

Guardrail:

- `ops/scripts/ha/proxmox-ha-audit.sh` FAILS if Proxmox HA resources exist when
  policy expects none (or vice versa).

## 4) Placement Validation

Placement validation is **read-only** and uses Terraform-derived inventory:

- Command: `make ha.placement.validate`
- Policy source: `fabric-core/ha/placement-policy.yml`
- Output: PASS/FAIL with concrete violations

## 5) Evidence Snapshot (Read-only)

GameDay and readiness evidence must be captured using the standard snapshot tool:

- Command: `make ha.evidence.snapshot`
- Output: `artifacts/ha-evidence/<UTC>/report.md`

The snapshot records:

- Proxmox cluster status
- VIP ownership for DNS/MinIO/Shared services
- Readiness of shared services over TLS
- Loki ingestion quick check
- SDN pending/apply status

## 6) Non-Goals

Phase 3 Part 1 **does not**:

- Enable Ceph
- Start destructive failure simulations
- Modify DNS/MinIO/shared service architecture
- Reconfigure Proxmox HA automatically
