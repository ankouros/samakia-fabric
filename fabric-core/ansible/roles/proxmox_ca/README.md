# proxmox_ca

Installs the Proxmox Root CA certificate on managed hosts so that
Terraform, curl, and other tools can communicate with the Proxmox API
using strict TLS verification.

## Why

By default Proxmox uses a self-signed or internal CA.
This role exists so you can keep strict TLS verification (no insecure flags).

## Usage

```yaml
- hosts: all
  become: true
  roles:
    - proxmox_ca
