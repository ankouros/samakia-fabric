# SSH Trust and Known Hosts Rotation

Strict SSH host key checking is mandatory in Samakia Fabric.
Host key rotation is required whenever a container is replaced or rebuilt.

## When this is required

- Any replace/recreate of an LXC container
- Any rebuild that changes the host key (new template, new VMID)

## Safe rotation workflow

1. Remove the old key entry:

```bash
ssh-keygen -R <host-or-ip>
```

2. Verify the new fingerprint out-of-band:

- Use the Proxmox console for the target CT/VM.
- Run `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` (or RSA if needed).
- Compare the fingerprint to the first SSH connection prompt.

3. Reconnect and accept the new key:

```bash
ssh <user>@<host-or-ip>
```

## Explicitly forbidden

- Disabling strict host key checking (`StrictHostKeyChecking no`)
- Blanket `UserKnownHostsFile=/dev/null`
- Re-adding keys without an out-of-band verification step

## Notes

- Strict SSH checking protects against MITM and stale host key reuse.
- Treat key rotation as part of the replace/recreate workflow.
