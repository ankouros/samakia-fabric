# Proxmox HA Failure Simulation (GameDays / Chaos Tests) — Safe, Reversible, Evidence-first

This runbook defines **production-grade, operator-driven** HA failure simulations (“GameDays”) for a Proxmox cluster running Samakia Fabric workloads.

Hard rules (non-negotiable):
- **Test in dev first**, then promote the runbook updates to prod.
- No automation that shuts down nodes, partitions networks, or changes HA policy.
- No root SSH enablement; break-glass remains console-only.
- No insecure TLS; internal CA trust model unchanged.
- Simulations must not create permanent drift. Any unintended drift is treated as a finding.

Guiding principle:
GameDays validate preparedness. They must never become incidents.

---

## A) Principles & Safety

### Roles
- **Conductor**: runs the steps, owns stop/go decisions.
- **Observer**: watches outputs and timing, records evidence, does not “help” by changing systems.
- **Comms**: coordinates maintenance window and stakeholders (optional in dev, mandatory in prod).

### Blast radius control
- One scenario at a time.
- One canary workload group only (explicitly selected).
- Stop if the scenario expands beyond the target node/workload.

### Abort criteria (stop conditions)
Abort the GameDay immediately if any of these occur:
- Cluster becomes non-quorate or split-brain indicators appear.
- HA manager becomes unstable (resource state flapping, repeated relocations).
- Shared storage health degrades unexpectedly.
- A non-target critical workload is affected.
- Operators feel tempted to “fix it live” by manual changes.

### Maintenance window guidance
- Dev: anytime with a single canary workload.
- Prod: planned window + comms + explicit rollback plan + pre/post evidence capture.

---

## B) Preconditions Checklist (Hard Gates)

Run these checks before any simulation.

### Cluster health
On a Proxmox node:
```bash
pvecm status
```
Expected: `Quorate: Yes`.

### HA manager health
```bash
systemctl is-active pve-ha-crm
systemctl is-active pve-ha-lrm
pve-ha-manager status
```
Expected: services active and HA manager reports healthy.

### Shared storage health (if used)
```bash
pvesm status
```
Expected: shared storage used by HA workloads is `active`.

### Target workload eligibility (migratable + HA-managed)
Hard gate: only test **HA-enabled** CTs that are expected to migrate or restart via Proxmox HA.

Recommended read-only helper:
```bash
bash ops/scripts/ha-precheck.sh --ctids 1100 1101
```

### Evidence readiness (recommended)
Before prod GameDays:
- Run drift/audit and/or compliance snapshot and keep it as the “baseline”.
  - `bash ops/scripts/drift-audit.sh <env>`
  - `bash ops/scripts/compliance-snapshot.sh <env>` (signed; dual-control/TSA per policy)

---

## C) Test Inventory & Tagging (Choosing Targets)

Choose targets intentionally:
- Only HA-managed resources (e.g., `lxc:<vmid>` appears in HA manager status).
- Prefer a **canary service group** with clear health checks and low impact.
- Map targets to failure domains:
  - node / rack / power domain (documented in `OPERATIONS_HA_FAILURE_DOMAINS.md`)
  - storage domain (shared NFS/Ceph vs local)

Record (minimum):
- CTID(s), service name(s), “tier” (critical vs non-critical), expected node placement policy.

---

## D) Scenarios (Repeatable, Safe)

Each scenario includes: goal → execution → expected → verify → rollback → evidence.

### Scenario 1 — Planned node reboot (HA relocation / restart)

Goal:
- Validate that HA-managed CTs recover (relocate/restart) per policy when a node becomes unavailable.

Setup:
- Select **one** target node and **one** canary HA workload group.
- Confirm targets are HA-managed:
  ```bash
  pve-ha-manager status | grep -E 'lxc:1100\\b|lxc:1101\\b'
  ```

Execution (operator-run; do not automate here):
- Announce the test window.
- Perform a planned reboot of the target node using your standard ops method (console or IPMI if applicable).

Expected behavior:
- HA relocates CTs to other eligible nodes or restarts them as configured.
- No infinite relocate/restart loops.

Verification (read-only):
```bash
pvecm status
pve-ha-manager status

# Per CTID:
bash ops/scripts/ha-sim-verify.sh 1100
bash ops/scripts/ha-sim-verify.sh 1101
```

Rollback:
- If recovery does not converge, stop and treat as a finding.
- Use documented HA recovery steps (no ad-hoc manual edits):
  - `OPERATIONS_HA_FAILURE_DOMAINS.md`

Post-test evidence:
- timestamps: start, node down, first relocation, service restored
- `pve-ha-manager status` output (before/after)
- any HA-related journal excerpts (read-only)

---

### Scenario 2 — Planned node evacuation (maintenance-mode behavior)

Goal:
- Validate that you can drain/migrate HA-managed CTs off a node before maintenance.

Execution:
- Use your standard Proxmox evacuation procedure (operator-run).
- Do not change HA group configs during the test.

Verification:
- All canary CTs are running on non-maintenance nodes.
- HA status is stable.

Rollback:
- Cancel maintenance; migrate back only if policy requires failback (document).

Evidence:
- list of CT placements before/after (node + CTIDs)

---

### Scenario 3 — Network isolation (safe mode)

Goal:
- Validate operational readiness for network loss without escalating to split-brain.

WARNING:
- Network partition tests can cause cluster instability. Treat as **advanced**.
- Do not perform in prod until runbooks are proven in dev and abort criteria are rehearsed.

Safe execution guidance (operator-run, scoped):
- Prefer a reversible, *single-node* maintenance action rather than “random firewalling”.
- Keep the window short.
- Monitor quorum continuously.

Verification (read-only):
```bash
pvecm status
pve-ha-manager status
```

Abort criteria (strong):
- If quorum is at risk or cluster membership changes unexpectedly: abort immediately and restore network.

Evidence:
- exact start/stop timestamps
- `pvecm status` outputs during the test

---

### Scenario 4 — HA restart storm resistance (max_restart/max_relocate behavior)

Goal:
- Validate that HA policy prevents endless restart loops and converges to a stable outcome.

Safe approach:
- Table-top first: confirm configured HA policy parameters for the target group/resource.
- In dev only: intentionally break the canary service at the application layer (outside this substrate) if you have an app-safe method.

Verification:
- HA does not thrash indefinitely.
- `pve-ha-manager status` shows bounded restart/relocate attempts.

Evidence:
- HA status outputs over time
- relevant HA logs (read-only)

---

### Scenario 5 — Storage outage simulation (table-top / limited)

Goal:
- Validate operator decision-making for shared storage failure domains.

Default mode:
- **Table-top only** unless you have a proven safe method in dev.

If you simulate in dev:
- Only with explicit approval and only if you can guarantee fast rollback.
- Do not test by “breaking all storage”; scope to a canary storage target if possible.

Verification:
- Understand which CTs are migratable and which are not.
- Confirm runbooks and stop conditions are clear.

Evidence:
- storage health outputs before/after
- HA status outputs before/after

---

## E) Observation & Verification Commands (Read-only)

Cluster/quorum:
```bash
pvecm status
```

HA status:
```bash
pve-ha-manager status
```

Per-CT placement + HA signals (helper):
```bash
bash ops/scripts/ha-sim-verify.sh <ctid>
```

Node-level read-only logs (best-effort):
```bash
journalctl -u pve-ha-crm -u pve-ha-lrm --no-pager -n 200
```

Container-level checks (allowed access model):
- `ssh samakia@<ip>` only (no root SSH)

---

## F) Post-test Review Template (03:00-safe)

Create a short post-test report:
- Scenario: (which one)
- Targets: (node, CTIDs, services)
- Start time (UTC):
- End time (UTC):
- Expected outcome:
- Observed outcome:
- Time to recovery:
- Any surprises:
- Abort criteria triggered? (yes/no)
- Runbook changes required:
- Recommendation: repeat in dev / promote to prod / block until fixed

---

## G) Evidence Capture & Audit Linkage (Recommended)

Recommended for prod GameDays:
- Pre-test: signed compliance snapshot (dual-control/TSA per policy)
- Post-test: signed compliance snapshot
- If the GameDay behaves like an incident: produce a forensics packet (facts-only) and apply legal hold if required:
  - `OPERATIONS_POST_INCIDENT_FORENSICS.md`
  - `OPERATIONS_LEGAL_HOLD_RETENTION.md`
  - `OPERATIONS_CROSS_INCIDENT_CORRELATION.md` (if patterns repeat)
