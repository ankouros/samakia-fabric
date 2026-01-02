# Tutorial Index

This index lists the recommended tutorial order for first-time setup.
Each step assumes the previous one is complete.

For day-2 operations and governance workflows, see `docs/operator/`.

## Required path

1. `01-bootstrap-proxmox.md` - Prepare Proxmox for strict TLS and delegated access.
2. `02-build-lxc-image.md` - Build and register the golden LXC image.
3. `03-deploy-lxc-with-terraform.md` - Create LXC infrastructure with Terraform.
4. `04-bootstrap-with-ansible.md` - Bootstrap hosts with Ansible policy.
5. `05-gitops-workflow.md` - Adopt the GitOps change model.
6. `06-bootstrap-remote-state-minio.md` - Bootstrap the Terraform remote state backend.
7. `07-deploy-dns-plane.md` - Deploy DNS infrastructure primitives.
8. `08-deploy-shared-services.md` - Deploy shared control-plane services.

## Notes

- All workflows are deterministic and non-interactive by default.
- Use strict TLS and a trusted Proxmox CA; never disable certificate verification.
- Evidence and artifacts are written under gitignored `evidence/` and `artifacts/` paths.
