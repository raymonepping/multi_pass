#!/usr/bin/env bash

# Runs as root inside one Terraform-managed lab guest.
set -euo pipefail

cleanup() {
  rm -f /tmp/vault /tmp/install-vault-guest.sh
}
trap cleanup EXIT HUP INT TERM

if ! getent passwd vault >/dev/null 2>&1; then
  /usr/sbin/useradd --system --home-dir /etc/vault.d --shell /sbin/nologin vault
fi

install -o root -g root -m 0755 /tmp/vault /usr/local/bin/vault
install -d -o root -g vault -m 0750 /etc/vault.d
install -d -o vault -g vault -m 0750 /opt/vault/data /opt/vault/tls

systemctl enable --now firewalld
firewall-cmd --permanent --add-port=8200/tcp >/dev/null
firewall-cmd --permanent --add-port=8201/tcp >/dev/null
firewall-cmd --reload >/dev/null

swapoff -a
sed -ri '/^[^#].+[[:space:]]swap[[:space:]]/ s/^/# vault-lab disabled: /' /etc/fstab

/usr/local/bin/vault version
