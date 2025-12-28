#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# Config (Golden Image contract)
# -----------------------------------------------------------------------------
TZ="${TZ:-UTC}"
LOCALE="${LOCALE:-en_US.UTF-8}"

# -----------------------------------------------------------------------------
# Base OS
# -----------------------------------------------------------------------------
apt-get update

# Core packages (keep minimal, but useful for ops)
apt-get install -y --no-install-recommends \
  systemd \
  systemd-sysv \
  dbus \
  ca-certificates \
  tzdata \
  locales \
  python3 \
  python3-apt \
  openssh-server \
  curl \
  jq \
  gnupg \
  iproute2 \
  iputils-ping \
  net-tools \
  dnsutils \
  sudo \
  rsyslog \
  tini

# NOTE:
# - Removed cloud-init: it is not reliably useful in LXC rootfs templates and
#   commonly adds confusion. We handle first-boot via SSH + Ansible.
#   (If you *really* want it later, add back with a clear datasource policy.)

# -----------------------------------------------------------------------------
# Locale / Timezone (neutral; operator can override later)
# -----------------------------------------------------------------------------
ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
echo "${TZ}" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

# Locale setup
sed -i "s/^# ${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen || true
locale-gen
update-locale "LANG=${LOCALE}"

# -----------------------------------------------------------------------------
# SSH hardening (no passwords; root only for bootstrap)
# -----------------------------------------------------------------------------
mkdir -p /run/sshd /var/run/sshd

sshd_cfg="/etc/ssh/sshd_config"

# Ensure PubkeyAuthentication is enabled
grep -q '^PubkeyAuthentication' "${sshd_cfg}" \
  && sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' "${sshd_cfg}" \
  || echo 'PubkeyAuthentication yes' >> "${sshd_cfg}"

# Disable passwords + interactive auth
grep -q '^PasswordAuthentication' "${sshd_cfg}" \
  && sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "${sshd_cfg}" \
  || echo 'PasswordAuthentication no' >> "${sshd_cfg}"

grep -q '^KbdInteractiveAuthentication' "${sshd_cfg}" \
  && sed -i 's/^KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "${sshd_cfg}" \
  || echo 'KbdInteractiveAuthentication no' >> "${sshd_cfg}"

# Allow root login with keys for bootstrap only
grep -q '^PermitRootLogin' "${sshd_cfg}" \
  && sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' "${sshd_cfg}" \
  || echo 'PermitRootLogin prohibit-password' >> "${sshd_cfg}"

# Hardening knobs
grep -q '^UseDNS' "${sshd_cfg}" \
  && sed -i 's/^UseDNS.*/UseDNS no/' "${sshd_cfg}" \
  || echo 'UseDNS no' >> "${sshd_cfg}"

grep -q '^X11Forwarding' "${sshd_cfg}" \
  && sed -i 's/^X11Forwarding.*/X11Forwarding no/' "${sshd_cfg}" \
  || echo 'X11Forwarding no' >> "${sshd_cfg}"

# Keep SSH enabled (systemd in container will start it when container boots)
systemctl enable ssh || true

# -----------------------------------------------------------------------------
# Basic OS hardening (LXC-safe)
# -----------------------------------------------------------------------------
# Disable unused services (if present)
systemctl disable systemd-resolved 2>/dev/null || true
systemctl disable snapd 2>/dev/null || true

# Lock root password (defense in depth)
passwd -l root || true

# Reduce noisy MOTD/update messages (optional)
chmod -x /etc/update-motd.d/* 2>/dev/null || true

# -----------------------------------------------------------------------------
# Immutability hygiene
# -----------------------------------------------------------------------------
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

rm -f /etc/ssh/ssh_host_* || true

# -----------------------------------------------------------------------------
# Notes:
# - Golden images are userless by design
# - Terraform injects temporary root SSH keys for bootstrap
# - Ansible creates non-root users and disables root SSH
# -----------------------------------------------------------------------------
