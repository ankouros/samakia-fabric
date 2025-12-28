# Samakia Fabric – Break-glass / Recovery Runbook

This runbook answers: **“I lost SSH access — what do I do?”**

Scope: **Ubuntu 24.04 LXC containers** created by Terraform and configured by Ansible.

---

## A) Preconditions / Invariants (DO NOT BREAK)

These are *non-negotiable* platform contracts:

- **Root SSH is disabled permanently** after bootstrap. Do **not** attempt to re-enable it.
- **Passwords are not used for SSH** (key-only).
- **Ongoing access is via** `ssh samakia@<ct-ip>`.
- **Proxmox API TLS is strict** and trusted via the **runner host trust store** (internal CA). No insecure flags.
- **No DNS dependency**: operate using IPs; inventory may resolve IP via `host_vars` → Proxmox API fallback.
- **Two-phase Ansible**:
  - Phase 1: `fabric-core/ansible/playbooks/bootstrap.yml` (root-only, minimal, one-shot)
  - Phase 2: `fabric-core/ansible/playbooks/harden.yml` (runs as `samakia` with `become: true`)

### Allowed access channels

- Proxmox UI **Console** for the container (break-glass interactive access)
- Proxmox node shell: `pct enter <vmid>` (requires node access)
- SSH as operator: `ssh samakia@<ct-ip>`

### Not allowed (even temporarily)

- Enabling root SSH
- Password SSH
- Insecure Proxmox API TLS flags / “skip verification”
- Introducing DNS dependency to “make it work”

---

## B) Triage decision tree (short)

1) **Do you have Proxmox UI access?**
- Yes → verify CT status + open Console → continue to recovery steps.
- No → go to (2).

2) **Do you have shell access on any Proxmox node?**
- Yes → use `pct` commands to verify CT status + enter CT → continue to recovery steps.
- No → this is a Proxmox access incident (out of scope for this runbook).

3) **Is the container running?**
- No → start it from Proxmox UI / node shell, then proceed.

4) **Did the IP change?**
- If unsure → resolve IP via Proxmox UI or node shell (see Section C.1).

---

## C) Recovery procedures (step-by-step)

### C.1 IP / connectivity recovery (no DNS)

Goal: determine the correct `<vmid>` and current `<ct-ip>`.

**From Proxmox UI**
1) Locate the CT by **VMID** / **hostname**.
2) Confirm it is **running**.
3) Open **Console** and run:
   - `ip -4 a`
   - `ip r`
4) Record the IPv4 address for `eth0` as `<ct-ip>`.

**From Proxmox node shell**
1) List containers:
   - `pct list`
2) Confirm identity and MAC pinning:
   - `pct config <vmid>`
3) Enter the container:
   - `pct enter <vmid>`
4) Inside the CT, find IP:
   - `ip -4 a`

**If DHCP changed**
- The platform assumes a **DHCP reservation exists for the pinned MAC**.
- Check the pinned MAC:
  - Proxmox UI: CT → Network
  - Proxmox node: `pct config <vmid>` (look for `hwaddr=...`)
- Verify the reservation on your DHCP server and ensure it maps to the expected `<ct-ip>`.

### C.2 Confirm the right CT (VMID / hostname)

Inside the CT (via Proxmox Console or `pct enter`):
- `hostnamectl --static` (or `hostname`)
- `ip -4 a` (confirm expected network segment)

Do not proceed until you are sure you are on the correct container.

### C.3 Restore `samakia` SSH key access (without root SSH)

This procedure uses **console-only root** as a break-glass channel.

1) Open Proxmox UI Console or run `pct enter <vmid>` on the node.
2) Ensure the user exists:
   - `id samakia`
   If missing, this indicates the container is not bootstrapped; recovery is to **recreate + bootstrap** (do not “patch around”).
3) Ensure SSH directory exists:
   - `install -d -m 700 -o samakia -g samakia /home/samakia/.ssh`
4) Add (or re-add) an authorized key:
   - `cat >> /home/samakia/.ssh/authorized_keys`
   - Paste the public key (`ssh-ed25519 ...`) and press Ctrl-D.
5) Fix ownership and permissions:
   - `chown -R samakia:samakia /home/samakia/.ssh`
   - `chmod 700 /home/samakia/.ssh`
   - `chmod 600 /home/samakia/.ssh/authorized_keys`
6) Verify you can SSH again from your workstation:
   - `ssh samakia@<ct-ip>`

### C.4 Undo a bad SSH daemon config change (keep contracts)

Symptoms:
- SSH suddenly stops accepting connections
- You see “connection reset”, “no matching algo”, or auth failures for a known-good key

Inside the CT (console/root channel):
1) Validate syntax before reloading:
   - `sshd -t`
2) If you use drop-ins, validate they exist and are readable:
   - `ls -la /etc/ssh/sshd_config.d/`
3) Check the Fabric hardening drop-in:
   - `/etc/ssh/sshd_config.d/50-samakia-hardening.conf`
4) If you need to roll back a broken drop-in:
   - `mv /etc/ssh/sshd_config.d/50-samakia-hardening.conf /root/50-samakia-hardening.conf.bak`
5) Validate again:
   - `sshd -t`
6) Reload SSH safely:
   - `systemctl reload ssh || systemctl restart ssh`
7) **Immediately verify**:
   - `ssh samakia@<ct-ip>`

Constraints:
- Do not set `PermitRootLogin` to anything other than `no`.
- Keep `AllowUsers samakia` policy intact after recovery (restore via `ansible-playbook playbooks/harden.yml` once access is restored).

### C.5 Firewall lockout recovery (UFW)

Baseline: firewall is **disabled by default**. If it was enabled explicitly and caused lockout:

Inside the CT (console/root channel):
1) Inspect:
   - `ufw status verbose`
2) Ensure SSH is allowed:
   - `ufw allow 22/tcp`
   - If you must scope it: `ufw allow from <mgmt-cidr> to any port 22 proto tcp`
3) If still locked out and you need immediate recovery:
   - `ufw disable`
4) Verify:
   - `ssh samakia@<ct-ip>`
5) After access is restored, re-apply the baseline:
   - `ansible-playbook fabric-core/ansible/playbooks/harden.yml`

### C.6 Terraform-driven key rotation (safe, no lockout)

Use this pattern **only for planned lifecycle events** (e.g., CT replacement / fresh bootstrap) where Terraform-provided SSH keys are required pre-bootstrap.

Rule: **never replace all keys at once**.

1) Add the **new** public key to the list (keep the old one):
   - `ssh_public_keys = ["<old-key>", "<new-key>"]`
2) Apply Terraform:
   - `terraform plan`
   - `terraform apply`
3) Recreate/bootstrap the new CT as usual:
   - `ansible-playbook fabric-core/ansible/playbooks/bootstrap.yml`
4) Validate operator access:
   - `ssh samakia@<ct-ip>`
5) Remove the old key in a second change and apply again.

### C.7 Ansible re-application after recovery

Normal recovery path (post-access-restoration):
- Re-run **phase 2** hardening:
  - `ansible-playbook fabric-core/ansible/playbooks/harden.yml`

Bootstrap is **almost never** a recovery tool:
- Re-run **phase 1** `bootstrap.yml` only for **freshly created** containers that have not been bootstrapped.

IP-based run (no DNS, bypass dynamic inventory if needed):
- `ansible-playbook -i '<ct-ip>,' fabric-core/ansible/playbooks/harden.yml`

---

## D) Golden rules (print this)

- Always keep **at least two** operator keys during rotations.
- Always validate `ssh samakia@<ct-ip>` **before** closing a Proxmox Console session.
- Never re-enable root SSH.
- Never use insecure TLS flags for Proxmox API.
- If bootstrap artifacts are missing (no `samakia` user), recover by **recreate + bootstrap**, not manual drift repair.

---

## E) Quick commands appendix

### Proxmox (node shell)

```bash
pct list
pct config <vmid>
pct enter <vmid>
```

### Linux inside CT (console / pct enter)

```bash
ip -4 a
ip r

systemctl status ssh
sshd -t
systemctl reload ssh || systemctl restart ssh

journalctl -u ssh -n 200 --no-pager
# (if present)
tail -n 200 /var/log/auth.log

ufw status verbose
```
