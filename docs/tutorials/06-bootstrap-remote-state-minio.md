# Tutorial 06 - Bootstrap Terraform Remote State (MinIO)

This tutorial bootstraps the Terraform remote state backend for Samakia Fabric.
The backend is required before running most production environments.

---

## 1. Scope

This tutorial covers:

- Runner preflight (CA trust and env file)
- MinIO backend deployment
- Acceptance and backend smoke checks
- State migration to S3

This tutorial does NOT cover:
- DNS or shared services (see Tutorials 07 and 08)
- Any workload exposure or application deployment

---

## 2. Prerequisites

- Tutorials 01 through 05 completed
- Proxmox internal CA installed on the runner host
- Runner env file installed at `~/.config/samakia-fabric/env.sh`
- Delegated Proxmox API token available (no root automation)

---

## 3. Runner Preflight

From the repo root:

```bash
export FABRIC_REPO_ROOT="$(git rev-parse --show-toplevel)"

bash "$FABRIC_REPO_ROOT/ops/scripts/install-proxmox-ca.sh"
bash "$FABRIC_REPO_ROOT/ops/scripts/runner-env-install.sh"
bash "$FABRIC_REPO_ROOT/ops/scripts/runner-env-check.sh"
```

If your S3 backend uses an internal CA not already trusted:

```bash
bash "$FABRIC_REPO_ROOT/ops/scripts/install-s3-backend-ca.sh"
```

---

## 4. Deploy MinIO Backend

```bash
make minio.up ENV=samakia-minio
```

This target runs Terraform apply, bootstrap, and acceptance in a guarded order.
It is non-interactive by default.

---

## 5. Acceptance and Smoke Checks

```bash
make minio.accept
make minio.backend.smoke ENV=samakia-minio
make minio.converged.accept ENV=samakia-minio
```

These checks are read-only and strict TLS is enforced.

---

## 6. Migrate Terraform State

After acceptance passes, migrate state to the remote backend:

```bash
make minio.state.migrate ENV=samakia-minio
```

---

## 7. Optional Safety Gate

```bash
make minio.quorum.guard ENV=samakia-minio
```

---

## 8. What Is Next

Proceed to:
- `docs/tutorials/07-deploy-dns-plane.md`
