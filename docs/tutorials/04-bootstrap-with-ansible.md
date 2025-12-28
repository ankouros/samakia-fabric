# Tutorial 04 – Bootstrap LXC Containers with Ansible

This tutorial describes how to perform **initial bootstrap**
of LXC containers using **Ansible** after they are created by Terraform.

Ansible enforces **policy and configuration**, not identity or infrastructure.

---

## Scope

This tutorial covers:
- Ansible inventory sourced from Terraform
- SSH access model for bootstrap
- Bootstrap playbook structure
- OS-level configuration
- Validation and idempotency

This tutorial does NOT cover:
- Application deployment
- Continuous drift repair
- Terraform responsibilities

---

## Ansible Philosophy in Samakia Fabric

Ansible is responsible for:
- Enforcing OS configuration
- Applying security baselines
- Preparing runtime environments

Ansible is NOT responsible for:
- Creating infrastructure
- Defining host identity
- Fixing broken images

If Ansible must “fix” the image, the image is wrong.

---

## Directory Structure

Ansible code lives under:

```text
fabric-core/ansible/
├── ansible.cfg
├── inventory/
│   └── terraform.py
├── inventories/
│   └── samakia/
├── host_vars/
├── group_vars/
├── playbooks/
└── roles/
```

Terraform feeds inventory. Ansible consumes it.

---

## Inventory from Terraform (Mandatory)

Inventory is generated from Terraform outputs.

Example:

```bash
ansible-inventory -i inventory/terraform.py --list
```

Expected output includes hosts created by Terraform.
Manual inventories are forbidden for production.

---

## SSH Access Model

Bootstrap requirements:
- Root SSH access is temporary and key-only
- SSH key is injected by Terraform
- Password login is disabled

Bootstrap flow:
1. Ansible connects as root for first bootstrap
2. Ansible creates the non-root operator user
3. Ansible installs authorized keys and sudo policy
4. Ansible disables root SSH access

Bootstrap requires `bootstrap_authorized_keys` to be provided at run time.

Example `secrets/authorized_keys.yml` (do not commit):

```yaml
bootstrap_authorized_keys:
  - "ssh-ed25519 REPLACE_WITH_PUBLIC_KEY"
```

Bootstrap will fail if no authorized keys are provided to prevent lockout.
The default bootstrap user is `samakia` and can be overridden with `-e bootstrap_user=...`.

---

## Host Variables

If host-level overrides are required:

```yaml
ansible_user: root
ansible_become: true
ansible_become_method: sudo
```

Avoid hardcoded IPs unless explicitly required.

---

## Global Defaults

Example `group_vars/all.yml`:

```yaml
ansible_python_interpreter: /usr/bin/python3
ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
```

Avoid per-host hacks.

---

## Bootstrap Playbook

Example `playbooks/bootstrap.yml`:

```yaml
- name: Bootstrap LXC hosts
  hosts: all
  become: true
  gather_facts: true

  tasks:
    - name: Ensure base packages are installed
      apt:
        name:
          - curl
          - jq
          - ca-certificates
          - rsyslog
        state: present
        update_cache: true

    - name: Ensure time synchronization
      command: timedatectl set-timezone UTC
      changed_when: false

    - name: Harden SSH configuration
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^PasswordAuthentication'
        line: 'PasswordAuthentication no'
      notify: restart ssh

  handlers:
    - name: restart ssh
      service:
        name: ssh
        state: restarted
```

Bootstrap must be idempotent.

---

## Running the Bootstrap

From the Ansible directory:

```bash
ansible-playbook playbooks/bootstrap.yml -u root -e @secrets/authorized_keys.yml
```

Expected result:
- Hosts reachable
- Tasks complete without errors
- Re-running produces no changes

---

## Idempotency Check

Run again:

```bash
ansible-playbook playbooks/bootstrap.yml -u root
```

Expected:
- No changes
- No failures

If not, fix the playbook.

---

## Validation

Verify manually (read-only):

```bash
ssh samakia@monitoring-1 uptime
```

Never fix issues manually.

---

## When Bootstrap Fails

Common causes:

| Symptom        | Root Cause                         |
|----------------|-------------------------------------|
| SSH denied     | Root SSH disabled or key missing    |
| Sudo fails     | Bootstrap policy misconfigured      |
| Package errors | Image missing baseline packages     |
| Drift          | Manual changes                      |

All fixes go back to image or code.

---

## Bootstrap vs Configuration Management

Bootstrap:
- Runs once per lifecycle
- Prepares the system

Configuration management:
- Enforces policy
- May run periodically

Do not mix concerns.

---

## Bootstrap and Replacement

When a container is replaced:
- Terraform recreates it
- Ansible bootstrap runs again
- No manual intervention required

This is the goal.

---

## Security Notes

- No secrets in playbooks
- No credentials in Git
- SSH keys managed externally
- Compromised hosts are destroyed

Ansible is not a security boundary.

---

## Anti-Patterns (Explicitly Rejected)

- SSH fixes after bootstrap
- Ansible as a patch tool
- Host-specific hacks
- Long-lived mutable containers

These break the lifecycle model.

---

## What’s Next

After bootstrap:
- `docs/tutorials/05-gitops-workflow.md`

This will cover:
- Change flow
- Reviews
- Rollbacks
- Day-2 operations

---

## Final Rule

If Ansible bootstrap is required to make a container usable,
the image is broken.

Fix the image. Rebuild.
