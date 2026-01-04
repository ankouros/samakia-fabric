# Shared VLAN IP/VIP Allocation Contract

This document explains the shared VLAN IP/VIP allocation contract for Samakia
Fabric. The authoritative source of truth is:

- `contracts/network/ipam-shared.yml`

No IP or VIP allocations are valid unless they are derived from that contract.

## Visual map (VLAN120: 10.10.120.0/24)

Ranges are allocation blocks within the shared VLAN. The CIDR denotes the block
size starting at the specified IP (even when the start is not a subnet boundary).

```
VIP range       10.10.120.0/29   (.0-.7)  VRRP/Keepalived VIPs only
Proxy range     10.10.120.8/29   (.8-.15) HAProxy/ingress nodes
Workload range  10.10.120.16/27  (.16-.47) Stateful service nodes
Mgmt range      10.10.120.48/28  (.48-.63) Management-only nodes
```

Notes:
- The VIP range contains virtual IPs only. VIPs are never assigned to node
  interfaces and are referenced by role, not hostname.
- Proxy nodes may appear in DNS A records; VIPs must not be primary DNS targets.
- Workload nodes are accessed through proxy layers and are not direct client
  endpoints.

## DNS policy (short form)

- DNS resolves to proxy nodes, not VIPs.
- VIPs are implementation details used for internal failover only.

## Example: Postgres Patroni cluster (internal)

- Patroni nodes (workload range): `10.10.120.23`, `10.10.120.24`,
  `10.10.120.25`
- HAProxy nodes (proxy range): `10.10.120.13`, `10.10.120.14`
- VIP (registry): `10.10.120.2` (`postgres_internal`)
- DNS: points to HAProxy nodes, not the VIP

## Example: HAProxy + VIP for observability

- Observability nodes (workload range): `10.10.120.31`, `10.10.120.32`
- HAProxy nodes (proxy range): `10.10.120.11`, `10.10.120.12`
- VIP (registry): `10.10.120.3` (`observability_shared`)
- DNS: points to HAProxy nodes, not the VIP

## What Codex is allowed to do

- Allocate new IPs and VIPs **only** within the ranges defined in
  `contracts/network/ipam-shared.yml`.
- Reserve new VIPs by adding them to the `vip_registry` with a role and
  keepalived group.
- Propose range expansions by updating the contract and documenting the change
  in `ROADMAP.md` and `CHANGELOG.md`.

## What Codex must never do

- Guess or invent IPs that are not defined in the contract.
- Reuse or repurpose a VIP for a different role.
- Assign a VIP directly to a node interface or use it as a management IP.
- Point DNS records directly at VIPs.
- Allocate tenant addresses from the management or VIP ranges.
