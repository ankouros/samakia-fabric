# Proxmox HA & Failure Domains — Operations Runbook

This document defines how Samakia Fabric approaches **Proxmox-level High Availability (HA)** with explicit **failure domain thinking**.

Contract reminders (non-negotiable):
- Proxmox HA is **best-effort restart/relocation**. It is not application-level HA.
- HA actions are **operator-driven** (runbooks), not silent automation.
- Terraform must not mutate Proxmox HA state; any enablement is a deliberate operator step.
- LXC workloads must be **rebuildable**; promotion/pinning remains Git-driven.

---

## A. Definitions

### Failure domain (in this cluster)
A failure domain is a boundary where a single incident can take down multiple components:
- **Node**: a single Proxmox host (hardware failure, reboot, kernel panic).
- **Rack / Power (PDU/UPS)**: multiple nodes share power/cooling.
- **Storage**: shared NFS outage, Ceph degradation/down (only if present).
- **Network segment**: cluster network vs management network vs storage network.

### What “HA” means for LXC in Proxmox
For LXC containers managed by Proxmox HA:
- On **node failure**, Proxmox can **restart** or **relocate** eligible containers onto other nodes.
- HA relies on **cluster quorum** and correct HA group configuration.
- HA requires **migratability** (primarily: shared storage availability + operationally safe service model).

---

## B. Cluster Topology Model (placeholders)

### Nodes
Use this format for operator documentation and change review:
- `proxmox1` — `fd-node=proxmox1`, `fd-rack=rack-a`, `fd-power=pdu-a`
- `proxmox2` — `fd-node=proxmox2`, `fd-rack=rack-a`, `fd-power=pdu-b`
- `proxmox3` — `fd-node=proxmox3`, `fd-rack=rack-b`, `fd-power=pdu-a`

### Storage
Document exactly what exists; do not assume.
- Shared NFS (example): `pve-nfs` (migratable if all nodes mount it consistently)
- Ceph: only if the cluster explicitly has it (then add Ceph-specific runbooks)
- Local storage: **not migratable** for HA purposes

### Networking
Document the boundaries:
- Proxmox **cluster network** (corosync): must be stable/low-latency
- Proxmox **management network**: API + SSH to nodes (operators)
- **Workload network**: bridges/SDN used by LXC

No DNS dependency: IP-based workflows are the default.

---

## C. Placement & Anti-Affinity Strategy

### Workload tiers
Classify containers as:
- **tier=critical**: business-impacting; should be HA-managed when eligible
- **tier=noncritical**: best-effort; may be fixed to a node if justified

### Anti-affinity rules (operator policy)
Anti-affinity is enforced by placement decisions (and documented tags), not hidden automation.
- Two containers of the same service group (`svc=monitoring`, `svc=db`, etc.) must not share the same **node**.
- For rack/power failure domains, do not place replicas in the same `fd-rack` or `fd-power` when possible.

### Tagging conventions (metadata-only, safe)
Use simple, Proxmox-safe tags (token style; no secrets):
- `tier-critical` / `tier-noncritical`
- `svc-monitoring` / `svc-db` / `svc-mq` / `svc-lb`
- `fd-rack-a` / `fd-rack-b`
- `fd-power-pdu-a` / `fd-power-pdu-b`
- `storage-shared-nfs` / `storage-local`
- `ha-eligible` / `ha-ineligible`

These tags are **hints** for humans and audits. They do not auto-enable HA.

---

## D. Proxmox HA Primitives Mapping (operator-run)

### Preconditions (must be true before enabling HA anywhere)
Run on a Proxmox node (or via the UI):
- Cluster health / quorum:
  - `pvecm status`
  - Expect: quorum OK, all nodes visible
- HA manager health:
  - `ha-manager status`
  - Expect: manager active, no stuck resources

### HA groups (how we will use them)
Define HA groups to express allowed nodes + preference ordering.

Operator workflow (example; verify flags with `ha-manager help` on your Proxmox version):
1. Create group (nodes listed in preference order):
   - `ha-manager groupadd ha-critical --nodes proxmox1,proxmox2,proxmox3`
2. Set policy knobs explicitly (example fields; keep conservative defaults unless you have a tested reason):
   - max restarts before relocate
   - max relocations before giving up
   - failback behavior (often disabled to avoid thrash)

### Adding an LXC to HA (deliberate, per resource)
Only after passing the “HA eligibility checklist” (section E).
- Add:
  - `ha-manager add ct:<vmid> --group ha-critical`
- Verify:
  - `ha-manager status`
  - `ha-manager config`

### Removing / disabling HA for a container (rollback-safe)
If HA causes unexpected behavior or the workload is found ineligible:
- Disable (stop HA actions without deleting config):
  - `ha-manager set ct:<vmid> --state disabled`
- Or remove from HA (if appropriate):
  - `ha-manager remove ct:<vmid>`

Rollback principle: disable first, observe, then remove if needed.

---

## E. Storage Failure Domains & HA Eligibility

### “Migratable” definition (for LXC)
A container is migratable/HA-eligible only if all are true:
- Rootfs and any attached volumes live on **shared storage** mounted identically on all target nodes (e.g., `pve-nfs`).
- The service is **restartable** and does not depend on local-only state.
- Network identity is deterministic (DHCP reservation via pinned MAC is acceptable).
- You have a tested bootstrap/hardening pipeline to recreate the container if needed.

### Shared NFS outage scenario (failure domain: storage)
Impact:
- HA cannot restart/migrate workloads if the shared storage that backs them is unavailable.
Operator stance:
- Treat storage outages as a **platform incident**, not an HA “auto-fix” event.

### Local storage containers (non-migratable)
Policy:
- Mark as `ha-ineligible`, `storage-local`, `tier-noncritical` unless there is a compelling, documented reason.
- Do not place these under Proxmox HA groups. If you do, you will get unpredictable behavior under failure.

### Ceph (only if present)
Do not enable HA based on an assumption of Ceph.
If Ceph exists, add a specific appendix with:
- degraded/backfill thresholds
- “stop-the-bleeding” steps
- when to block migrations

---

## F. Network Partitions / Split-Brain (quorum reality)

Proxmox HA is unsafe without quorum.

### What to check (before doing anything)
On each reachable node:
- `pvecm status`
- `pvecm nodes`
- Confirm which side has quorum.

### Do-not-do list (make it worse fast)
- Do not “force” cluster membership/quorum without a documented incident procedure.
- Do not perform simultaneous conflicting actions from two partitions (e.g., starting the same HA resource on both sides).
- Do not assume HA will “sort it out”.

Containment principle: stabilize quorum first, then deal with workload recovery.

---

## G. Recovery Runbooks (step-by-step)

### 1) Node failure (unexpected)
Goal: confirm HA behavior and restore service with minimal human intervention.

1. Confirm node is down:
   - `pvecm status` (from a surviving node)
2. Check HA manager decisions:
   - `ha-manager status`
3. Confirm affected resources:
   - Look for `ct:<vmid>` transitions and target node assignment.
4. Verify service health at the app layer (HA is not app HA).
5. If HA is thrashing (restarts/relocates repeatedly):
   - Disable the resource:
     - `ha-manager set ct:<vmid> --state disabled`
   - Investigate root cause (storage, network, app crash-loop) before re-enabling.

Rollback: keep HA disabled until the system is stable.

### 2) Node returns (post-incident)
Goal: avoid ping-pong “failback thrash”.

1. Confirm quorum is stable:
   - `pvecm status`
2. Confirm HA is stable:
   - `ha-manager status`
3. Decide failback policy:
   - Default recommendation: **no automatic failback** (do not chase “preferred” nodes during recovery).
4. If you want to re-balance manually, do it explicitly during a maintenance window:
   - Move workloads one by one (UI or CLI), verify app health after each.

### 3) Shared storage outage (NFS)
Goal: contain blast radius and avoid making storage recovery harder.

1. Confirm storage health:
   - On nodes: check the shared mount is reachable and consistent.
2. Freeze churn:
   - Disable HA-managed resources that are flapping due to storage errors:
     - `ha-manager set ct:<vmid> --state disabled`
3. Restore storage first (platform incident).
4. Re-enable resources deliberately:
   - `ha-manager set ct:<vmid> --state started`
5. Post-incident: validate that the workload’s state model is compatible with HA expectations.

Rollback: keep HA disabled for affected resources until storage stability is proven.

### 4) Planned maintenance (evacuate a node)
Goal: move workloads off a node safely without triggering surprise HA actions.

1. Identify workloads on the node:
   - `pct list` (on that node)
2. For HA-managed containers:
   - Prefer UI-managed migration/relocation so HA state stays coherent.
   - If a resource is HA-managed and you need deterministic control, disable it temporarily, migrate, then re-enable:
     - `ha-manager set ct:<vmid> --state disabled`
     - migrate via UI (or `pct migrate <vmid> <target-node>`)
     - `ha-manager set ct:<vmid> --state started`
3. Verify after each move:
   - SSH reachability (`ssh samakia@<ip>`)
   - Application health checks

Rollback: migrate back (or re-enable HA without moving further) if issues appear.

---

## H. Safety Gates (before enabling HA on any CT)

Enable HA only when all gates pass:
- Template version is pinned (no “latest”); promotion is Git-driven.
- Bootstrap completed; `ssh root@<ip>` fails; `ssh samakia@<ip>` works.
- Hardening completed; repeat runs are idempotent.
- Rootfs/volumes are on **shared storage** if migration is expected.
- The workload has an app-level recovery story (replication, external state, or is stateless).
- Failure domain intent is tagged (`tier-*`, `svc-*`, `fd-*`, `ha-eligible`).

If any gate fails: do not enable HA. Fix the workload model first.

---

## I. GameDays / Failure Simulation

Run HA failure simulations in dev before prod, with strict safety gates, abort criteria, and evidence capture guidance:
- `OPERATIONS_HA_FAILURE_SIMULATION.md`
