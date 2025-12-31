# Proxmox Template Registration (Guarded)

Phase 8 Part 2 provides a **guarded** workflow to register a locally built qcow2
VM image as a Proxmox template. This is **opt-in** and **token-only**.

## Preconditions

- Proxmox API token only (no passwords)
- Strict TLS (Proxmox CA installed on runner)
- VM image contract updated with real `sha256` (no placeholders)
- qcow2 artifact available locally
- Environment allowlisted in `ops/images/vm/register/register-policy.yml`

## Required Proxmox privileges (role grants)

Minimal privileges for template registration (token scope):

- `VM.Allocate`
- `VM.Audit`
- `VM.Config.CPU`
- `VM.Config.Memory`
- `VM.Config.Disk`
- `VM.Config.Network`
- `VM.Config.Options`
- `VM.Config.HWType`
- `VM.Config.Cloudinit`
- `VM.Template`
- `VM.PowerMgmt`
- `Datastore.AllocateSpace`
- `Datastore.Audit`

Adjust as needed to match your storage backend.

## Guarded registration (example)

```bash
export PM_API_URL="https://proxmox1:8006/api2/json"
export PM_API_TOKEN_ID="terraform-prov@pve!fabric-token"
# PM_API_TOKEN_SECRET is set in ~/.config/samakia-fabric/env.sh

IMAGE_REGISTER=1 \
I_UNDERSTAND_TEMPLATE_MUTATION=1 \
REGISTER_REASON="initial vm template register" \
ENV=samakia-dev \
TEMPLATE_NODE=proxmox1 \
TEMPLATE_STORAGE=pve-nfs \
TEMPLATE_VM_ID=9001 \
QCOW2=/path/to/ubuntu-24.04.qcow2 \
make image.template.register IMAGE=ubuntu-24.04 VERSION=v1
```

### Optional replace (destructive)

```bash
IMAGE_REGISTER=1 \
I_UNDERSTAND_TEMPLATE_MUTATION=1 \
REGISTER_REPLACE=1 \
I_UNDERSTAND_DESTRUCTIVE=1 \
REGISTER_REASON="replace corrupted template" \
ENV=samakia-dev TEMPLATE_NODE=proxmox1 TEMPLATE_STORAGE=pve-nfs TEMPLATE_VM_ID=9001 \
QCOW2=/path/to/ubuntu-24.04.qcow2 \
make image.template.register IMAGE=ubuntu-24.04 VERSION=v1
```

## Verify a template (read-only)

```bash
ENV=samakia-dev \
TEMPLATE_NODE=proxmox1 \
TEMPLATE_STORAGE=pve-nfs \
TEMPLATE_VM_ID=9001 \
make image.template.verify IMAGE=ubuntu-24.04 VERSION=v1
```

## Evidence packets

Evidence is written under:

```
evidence/images/vm/<image>/<version>/<UTC>/register/
evidence/images/vm/<image>/<version>/<UTC>/verify/
```

Each packet includes:
- `report.md`
- `metadata.json`
- `qcow2.sha256`
- `contract.sha256`
- `manifest.sha256`
- optional `manifest.sha256.asc` (if signing enabled)

## Rollback (guarded)

Delete a template only with an explicit destructive guard and reason.
Do **not** remove templates without recording evidence and a reason.

## Strict TLS reminder

No `-k`/`--insecure` is allowed. Ensure the Proxmox CA is installed:

```bash
bash ops/scripts/install-proxmox-ca.sh
```
