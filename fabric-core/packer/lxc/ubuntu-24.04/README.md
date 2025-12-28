# Ubuntu 24.04 LTS – LXC Golden Image

This directory contains the Packer configuration to build a minimal,
hardened Ubuntu 24.04 LTS rootfs for Proxmox LXC templates.

## Contents

- `packer.pkr.hcl`: Packer build definition
- `provision.sh`: baseline OS setup and hardening
- `cleanup.sh`: image hygiene and cleanup

## Usage

See `docs/tutorials/02-build-lxc-image.md` for the full build and validation flow.
