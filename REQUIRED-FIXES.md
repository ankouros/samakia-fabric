# REQUIRED-FIXES — MinIO Backend Automation Remediation Status

This document records what was fixed, what remains blocked (if anything), and the exact verification status for the MinIO backend automation in **Samakia Fabric**.

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

- None (as of the latest run).

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
