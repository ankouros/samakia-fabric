# Tutorial 07 - Deploy DNS Infrastructure

This tutorial deploys the DNS plane for Samakia Fabric.
The DNS plane is a Phase 2 primitive used by other services.

---

## 1. Scope

This tutorial covers:

- DNS SDN plane validation
- DNS infrastructure deployment
- DNS acceptance checks

This tutorial does NOT cover:
- Shared control-plane services (see Tutorial 08)
- Any workload exposure

---

## 2. Prerequisites

- Tutorial 06 completed (remote state backend ready)
- Proxmox internal CA installed on the runner host
- Runner env file installed at `~/.config/samakia-fabric/env.sh`

---

## 3. Optional SDN Precheck

```bash
make dns.sdn.accept ENV=samakia-dns
```

---

## 4. Deploy DNS Plane

```bash
make dns.up ENV=samakia-dns
```

This target applies Terraform, bootstraps, and runs acceptance checks.

---

## 5. Acceptance

```bash
make dns.accept ENV=samakia-dns
```

If you want the full Phase 2 acceptance gate:

```bash
ENV=samakia-dns make phase2.accept
```

---

## 6. What Is Next

Proceed to:
- `docs/tutorials/08-deploy-shared-services.md`
