# LXC Lifecycle Operations (Replace / Blue-Green) — Phase 1

This runbook covers **safe, production-oriented LXC lifecycle operations** under Samakia Fabric contracts:

- Images are immutable and version-pinned (`*-vN.tar.gz`)
- Terraform is lifecycle-only (no provisioning)
- Bootstrap is root-only and one-shot; hardening runs as `samakia` + `become`
- No DNS dependency
- Strict TLS to Proxmox API (internal CA trusted on runner)
- Root SSH must remain disabled after bootstrap

The substrate philosophy remains: **rebuild over repair**.

---

## A) Prerequisites (always)

1) Runner environment is configured (no secrets printed):

```bash
make runner.env.check
```

2) Drift is understood (read-only):

```bash
bash ops/scripts/drift-audit.sh samakia-prod
```

3) Inventory resolves without DNS (fail loud if not resolvable):

```bash
make inventory.check ENV=samakia-prod
```

---

## B) Replace “in-place” (same VMID) — simplest, destructive-by-design

Use this when:
- The workload is “cattle” (stateless or externalized state)
- You want to keep the same VMID and MAC reservation
- You accept a brief downtime window

### Steps

1) Promote/pin the desired template version in Git:
- Edit `fabric-core/terraform/envs/<env>/main.tf`:
  - `local.lxc_rootfs_version = "vN"`

2) Plan (read-only):

```bash
make tf.plan ENV=<env>
```

3) Apply deliberately:

```bash
make tf.apply ENV=<env>
```

4) Bootstrap and harden the new container:

```bash
make ansible.bootstrap ENV=<env>
make ansible.harden ENV=<env>
```

5) Validate access contracts:
- `ssh samakia@<ip>` succeeds
- `ssh root@<ip>` fails

### Known_hosts and replace/recreate

Because the container is rebuilt, its SSH host key changes.
Do not disable host key checking. Rotate trust explicitly:

```bash
make ssh.trust.rotate HOST=<ip>
make ssh.trust.verify HOST=<ip>
```

Enroll a new key only after out-of-band verification (console / change record).

---

## C) Blue/Green (new VMID + cutover) — safer cutovers, more work

Use this when:
- You want validation before switching traffic
- You can cut over at the application ingress layer (load balancer, client config, or service discovery)
- You can run two containers temporarily

### Steps

1) Add “green” alongside “blue”
- Add a second module instance in the same env with:
  - a new `vmid`
  - a new `hostname`
  - a new pinned `mac_address` (DHCP reservation required)
  - the same template pin and baseline sizing as appropriate

2) Apply (creates the new container):

```bash
make tf.apply ENV=<env>
```

3) Bootstrap/harden the new container:

```bash
make ansible.bootstrap ENV=<env>
make ansible.harden ENV=<env>
```

4) Validate health on the green container using IP-based access (no DNS).

5) Cut over traffic
- Perform the cutover at the application layer.
- Samakia Fabric does not assume any specific cutover mechanism (no DNS dependency; no Kubernetes assumption).

6) Decommission blue
- Remove the old module instance from Git.
- Apply again.

---

## D) DHCP/MAC determinism contract (critical)

Samakia Fabric assumes deterministic networking without DNS:

- Terraform pins a stable `mac_address` per container.
- Your DHCP server must have a matching reservation for that MAC.

If the reservation is missing, inventory resolution will fail loud.

Sanity check:

```bash
bash ops/scripts/inventory-sanity-check.sh <env>
```

If you pin `ansible_host` in `fabric-core/ansible/host_vars/<host>.yml`, keep it consistent with DHCP reservations.
