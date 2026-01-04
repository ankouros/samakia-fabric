# SDN Governance: Shared Internal Plane

Samakia Fabric treats SDN zones as **semantic planes**, not service groupings.
Internal shared services live on a single plane: `zshared` / `vshared` (VLAN120).

Authoritative contract:
- `contracts/network/shared-plane.yml`

## Core rule

All internal shared services MUST attach to `zshared` / `vshared`.
Service-specific zones or vnets are forbidden.

Segmentation is enforced through:
- firewall rules
- service-level authentication
- policy and evidence gates

## DO / DO NOT

| DO | DO NOT |
| --- | --- |
| Attach internal shared services to `zshared` / `vshared`. | Create service-specific zones (e.g. `zminio`, `zonedns`). |
| Use policy and firewalling for isolation. | Treat SDN plane sprawl as isolation. |
| Keep tenant workloads off the shared plane. | Place tenant workloads on `zshared` / `vshared`. |
| Plan migrations via Terraform/Ansible. | Manually mutate SDN primitives. |

## Migration policy

Legacy service-specific zones (`zminio`/`vminio`, `zonedns`/`vlandns`) are
considered **legacy**. They MUST NOT be reused or extended.

Migration to `zshared` / `vshared`:
- planned and explicit
- executed via Terraform/Ansible
- never manual

No immediate destruction occurs unless explicitly approved later.
