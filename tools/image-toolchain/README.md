# Image Toolchain Container

This container provides a **pinned, reproducible** toolchain for building and
validating VM golden image artifacts locally.

## What it is

- Packer (HCL2)
- Ansible
- qemu-img
- libguestfs / guestfish
- jq, yq, sha256sum
- gpg (optional signing)

## What it is NOT

- It does not register Proxmox templates.
- It does not provision VMs.
- It does not embed secrets or credentials.

## Build the container (optional)

```bash
docker build -t samakia-fabric/image-toolchain:phase8-1.2 tools/image-toolchain
```

## Run via wrapper

```bash
IMAGE_BUILD=1 I_UNDERSTAND_BUILDS_TAKE_TIME=1 \
ops/images/vm/toolchain-run.sh full --image ubuntu-24.04 --version v1
```

## Host requirements

- Docker or Podman (rootful)
- Enough disk for qcow2 outputs
- Optional: `--privileged` or `/dev/kvm` exposure if needed for Packer builds

## Version pins

Pinned versions live in `tools/image-toolchain/versions.env`.
If Debian package versions drift, update the pins accordingly.
