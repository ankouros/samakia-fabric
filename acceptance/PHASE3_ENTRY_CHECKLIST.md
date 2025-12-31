# Phase 3 Entry Checklist — High Availability & Resilience

Timestamp (UTC): 2025-12-30T22:23:02Z
Commit: f637914d31d4dd24b4dce86869291ed535710af2
Source: ROADMAP.md (Phase 3)

Scope confirmation (from ROADMAP.md):
- Proxmox HA-aware patterns (HA vs non-HA)
- Multi-node placement + anti-affinity
- Storage abstraction (NFS today, Ceph-ready)
- Failure-domain aware placement
- GameDays + evidence capture
- Explicitly NOT: Kubernetes, GitOps/CI/CD, security hardening beyond HA semantics

Phase closure verification (hard gate):
- Phase 0 acceptance marker present: PASS (acceptance/PHASE0_ACCEPTED.md)
- Phase 1 acceptance marker present: PASS (acceptance/PHASE1_ACCEPTED.md)
- Phase 2 acceptance marker present: PASS (acceptance/PHASE2_ACCEPTED.md)
- Phase 2.1 acceptance marker present: PASS (acceptance/PHASE2_1_ACCEPTED.md)
- REQUIRED-FIXES.md contains no OPEN items: PASS (inspection)

A. Platform Readiness
- Proxmox cluster health (nodes, quorum): PASS — `curl $PM_API_URL/cluster/status | python3` @ 2025-12-30T22:42:56Z (quorate=1, nodes=3, offline=none)
- Storage backend status (NFS healthy; Ceph readiness noted): PASS — `curl $PM_API_URL/storage` + `curl $PM_API_URL/nodes/proxmox1/storage/pve-nfs/status` @ 2025-12-30T22:42:56Z (active=1, ceph_total=0)
- SDN stability (no pending apply): PASS — `ENV=samakia-dns make dns.sdn.accept`, `ENV=samakia-minio make minio.sdn.accept`, `ENV=samakia-shared make shared.sdn.accept` @ 2025-12-30T22:42:56Z (shared check reports skips but PASS)
- VIP ownership stability: PASS — `ssh edge-mgmt ip addr show` holder check @ 2025-12-30T22:42:56Z (each VIP has exactly one holder)

B. Contract Integrity
- Phase 2 networking contracts unchanged: PASS — no Phase 2 modifications in this task
- Phase 2.1 shared services reachable: PASS — `ENV=samakia-shared make shared.ntp.accept`, `shared.vault.accept`, `shared.obs.accept` @ 2025-12-30T22:42:56Z
- Strict TLS posture enforced: PASS — no insecure flags introduced; contract unchanged
- Token-only Proxmox access enforced: PASS — contract unchanged

C. Observability Baseline
- Prometheus scraping infra nodes: PASS — `curl https://192.168.11.122:9090/api/v1/targets` @ 2025-12-30T22:42:56Z (targets_total=1, targets_up=1)
- Alertmanager operational: PASS — `curl https://192.168.11.122:9093/-/ready` @ 2025-12-30T22:42:56Z (http_code=200)
- Grafana reachable (read-only): PASS — `curl https://192.168.11.122:3000/` @ 2025-12-30T22:42:56Z (http_code=302)
- Loki logs flowing: FAIL — `curl https://192.168.11.122:3100/loki/api/v1/series?match[]={job=\"varlogs\"}` @ 2025-12-30T22:42:56Z (series_count=0)

D. Operational Safety
- Backup strategy documented: PASS — OPERATIONS.md references backup/restore notes
- Restore procedures documented: PASS — OPERATIONS.md references restore guidance
- Break-glass access documented: PASS — OPERATIONS_BREAK_GLASS.md present
- Known failure modes enumerated: PASS — `test -f OPERATIONS_HA_FAILURE_DOMAINS.md OPERATIONS_HA_FAILURE_SIMULATION.md` @ 2025-12-30T22:42:56Z

E. Governance
- Phase boundaries respected: PASS — no scope change
- No ADR conflicts: PASS — no ADR changes in this task
- No silent scope creep: PASS — governance-only task
- No automation yet — checklist only: PASS

Entry Decision:
- Phase 3 entry status: NOT READY
- Blocking gaps: Loki log ingestion not observed via VIP (series_count=0)

Evidence placeholders (to be filled when checks are executed):
- Proxmox cluster health: `curl $PM_API_URL/cluster/status` @ 2025-12-30T22:42:56Z
- SDN apply status: `make dns.sdn.accept`, `make minio.sdn.accept`, `make shared.sdn.accept` @ 2025-12-30T22:42:56Z
- VIP ownership: `ssh edge-mgmt ip addr show` @ 2025-12-30T22:42:56Z
- Observability checks: `curl .../targets`, `curl .../ready`, `curl .../series` @ 2025-12-30T22:42:56Z
