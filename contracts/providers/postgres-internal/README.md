# Postgres internal provider (Patroni)

This contract defines the **internal-only** shared Postgres service used by
Samakia Fabric for platform verification and implementation work.

## What it is

- HA Postgres cluster (Patroni) on the shared VLAN.
- Fronted by HAProxy + Keepalived VIP (proxy-first DNS).
- TLS passthrough via HAProxy; Postgres terminates TLS.
- Internal-only by default; no tenant exposure.

## When to use

- Phase 17 canary verification (`db.canary.internal` alias).
- Internal platform testing that requires a real Postgres endpoint.

## When not to use

- Tenant workloads (future opt-in only).
- Public exposure or tenant-facing access (forbidden).
- LAN access is limited to explicit operator allowlists.

## DNS and VIP policy

- Primary DNS: `db.internal.shared`
- Alias: `db.canary.internal`
- DNS resolves to HAProxy nodes, **not** to the VIP.
- VIP (`10.10.120.2`) is for internal failover only.

## Future tenant opt-in

Tenant use is explicitly out of scope. Any opt-in requires:

- A future Phase approval.
- Updated contracts and exposure policy.
- Explicit operator acceptance and evidence.

## References

- `topology.yml`
- `endpoints.yml`
- `policy.yml`
- `contracts/network/ipam-shared.yml`
