# Vault Access (Shared VLAN)

This document defines the **authoritative** access patterns for Vault in
Samakia Fabric. It is normative.

## Vault location

- Vault runs on the shared control-plane VLAN (`zshared`/`vshared`).
- Service endpoint: shared Vault VIP `192.168.11.121:8200` (TLS required).
- Off-VLAN hosts must not assume direct access.

## Supported access patterns

- **Shared-VLAN runner (preferred)**: run operator workflows from a runner
  attached to VLAN120 with direct reachability to the Vault VIP.
- **SSH port-forward (approved exception)**: tunnel to the Vault VIP through a
  shared-VLAN jump host.

## Unsupported patterns

- Direct off-VLAN access to Vault.
- Exposing Vault externally or through public ingress.

## Access setup (shared-VLAN runner)

```bash
export VAULT_ADDR="https://192.168.11.121:8200"
export VAULT_CACERT="$HOME/.config/samakia-fabric/pki/shared-bootstrap-ca.crt"
vault status
```

Notes:
- `VAULT_CACERT` may be omitted only if the shared bootstrap CA is already
  installed in the host trust store.
- `VAULT_TOKEN` is required for any read/write calls (never print it).

## Access setup (SSH port-forward)

```bash
# From an off-VLAN host, tunnel to a shared-VLAN jump host.
ssh -L 8200:192.168.11.121:8200 samakia@ntp-1.infra.samakia.net

export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_CACERT="$HOME/.config/samakia-fabric/pki/shared-bootstrap-ca.crt"
vault status
```

Notes:
- The jump host must be on the shared VLAN and permitted for SSH access.
- Do not change Vault firewall posture to "make it reachable"; use the tunnel.
