# Local VM Image Build + Validate Runbook

This runbook provides a strict, copy/paste local workflow to build and validate
VM golden images as **immutable artifacts**. It does **not** register templates
or provision VMs.

## Prerequisites

- `packer` (HCL2 support)
- `qemu-img`
- `ansible-playbook`
- `python3`

Optional (for deeper offline inspection):
- `libguestfs-tools` (includes `guestfish`)
- `virt-customize`

If building inside a VM, ensure nested virtualization is enabled.

### Quick tool check

```bash
make image.tools.check
```

## Golden path (Ubuntu 24.04 v1)

1) Build (guarded)

```bash
IMAGE_BUILD=1 make image.local.full IMAGE=ubuntu-24.04 VERSION=v1
```

2) Validate an existing qcow2 artifact (offline)

```bash
QCOW2_FIXTURE_PATH=/path/to/ubuntu-24.04-v1.qcow2 \
  make image.local.validate IMAGE=ubuntu-24.04 VERSION=v1 QCOW2=/path/to/ubuntu-24.04-v1.qcow2
```

3) Generate validation evidence (optional signing)

```bash
EVIDENCE_SIGN=1 EVIDENCE_GPG_KEY=<KEY_ID> \
  make image.local.evidence IMAGE=ubuntu-24.04 VERSION=v1 QCOW2=/path/to/ubuntu-24.04-v1.qcow2
```

4) Verify evidence

```bash
ops/images/vm/evidence/verify-evidence.sh --dir /path/to/evidence/dir
```

## Debian 12 v1 (example)

```bash
IMAGE_BUILD=1 make image.local.full IMAGE=debian-12 VERSION=v1
```

## Evidence locations

Evidence packets are written under:

```
evidence/images/vm/<image>/<version>/<UTC>/{build,validate}/
```

Artifacts and evidence must never be committed to Git.

## Failure modes (common)

- **missing guestfish**
  - Offline checks may fail if `guestfish` is not available.
  - Install `libguestfs-tools` and re-run validation.

- **qcow2 path mistakes**
  - Ensure `QCOW2` points to a local file and the path is absolute.

- **cloud-init validation failure**
  - Ensure cloud-init is installed and enabled in the image.

- **ssh posture failure**
  - Verify `PasswordAuthentication no` and `PermitRootLogin prohibit-password`.

- **package manifest missing**
  - Ensure `/etc/samakia-image/pkg-manifest.txt` exists in the image.

## Hygiene rules

- Never commit artifacts or evidence.
- Keep evidence redacted and secrets-free.
- Use only guarded build commands.
