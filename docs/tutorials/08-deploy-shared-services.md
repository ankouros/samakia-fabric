# Tutorial 08 - Deploy Shared Control-Plane Services

This tutorial deploys shared services (NTP, Vault, PKI, observability)
for Samakia Fabric. These services are Phase 2.1 and Phase 2.2 primitives.

---

## 1. Scope

This tutorial covers:

- Shared SDN plane and service deployment
- Shared services acceptance checks
- Phase 2.1 and 2.2 acceptance gates

This tutorial does NOT cover:
- Any workload exposure or tenant bindings

---

## 2. Prerequisites

- Tutorial 06 completed (remote state backend ready)
- Proxmox internal CA installed on the runner host
- Runner env file installed at `~/.config/samakia-fabric/env.sh`
- For local exception workflows, set `SECRETS_BACKEND=file` and `BIND_SECRETS_BACKEND=file` in the env file

---

## 3. Deploy Shared Services

```bash
make shared.up ENV=samakia-shared
```

This target applies Terraform, bootstraps shared hosts, and runs acceptance.

---

## 4. Acceptance

```bash
make shared.accept ENV=samakia-shared
```

Phase acceptance gates (read-only):

```bash
ENV=samakia-shared make phase2.1.accept
ENV=samakia-shared make phase2.2.accept
```

---

## 5. What Is Next

- Review `docs/operator/cookbook.md` for day-2 operations
- Review `docs/operator/phase12-exposure.md` for release readiness flows
