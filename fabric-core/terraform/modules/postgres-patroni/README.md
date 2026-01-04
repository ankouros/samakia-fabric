# Terraform Module: Postgres Patroni (Internal)

Provision LXC nodes for the internal Postgres HA service (Patroni) and its
HAProxy frontends on the shared VLAN.

## Scope

- LXC node lifecycle only (no provisioning).
- Explicit VLAN attachments and IPs.
- Deterministic Proxmox UI tags.

## Inputs

- `lxc_template` (string, required)
- `ssh_public_keys` (list, required)
- `storage` (string, required)
- `tag_env`, `tag_plane` (string, required)
- `vlan_vnet`, `vlan_gateway` (string, required)
- `patroni_nodes` (map, required)
- `haproxy_nodes` (map, required)

## Outputs

- `patroni_inventory`
- `haproxy_inventory`

## Notes

- Feature flags are immutable; networking changes are ignored by lifecycle.
- Provisioning is handled by Ansible roles (Patroni + HAProxy + Keepalived).
