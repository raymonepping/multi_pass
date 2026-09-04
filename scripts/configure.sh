#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd terraform
require_cmd multipass
require_cmd openssl
require_managed_nodes
[[ -f "${TLS_DIR}/ca.crt" ]] || die "TLS CA is absent. Run 'make tls' first."

hosts_file="$(mktemp "${TMPDIR:-/tmp}/vault-hosts.XXXXXX")"
config_file="$(mktemp "${TMPDIR:-/tmp}/vault-config.XXXXXX")"
trap 'rm -f "${hosts_file}" "${config_file}"' EXIT

for node in "${NODES[@]}"; do
  printf '%s %s # vault-lab\n' "$(node_ip "${node}")" "${node}" >>"${hosts_file}"
done

for node in "${NODES[@]}"; do
  ip="$(node_ip "${node}")"
  [[ -f "${TLS_DIR}/${node}.crt" && -f "${TLS_DIR}/${node}.key" ]] ||
    die "TLS material for ${node} is absent. Run 'make tls' first."

  info "Configuring ${node}"
  sed -e "s/@NODE@/${node}/g" -e "s/@IP@/${ip}/g" \
    "${ROOT_DIR}/templates/vault/vault.hcl.tpl" >"${config_file}"

  multipass transfer "${hosts_file}" "${node}:/tmp/vault-lab-hosts"
  multipass transfer "${config_file}" "${node}:/tmp/vault.hcl"
  multipass transfer "${ROOT_DIR}/templates/vault/vault.service" "${node}:/tmp/vault.service"
  multipass transfer "${TLS_DIR}/ca.crt" "${node}:/tmp/ca.crt"
  multipass transfer "${TLS_DIR}/${node}.crt" "${node}:/tmp/server.crt"
  multipass transfer "${TLS_DIR}/${node}.key" "${node}:/tmp/server.key"

  multipass exec "${node}" -- sudo sed -i '/# vault-lab$/d' /etc/hosts
  multipass exec "${node}" -- sudo sh -c 'cat /tmp/vault-lab-hosts >> /etc/hosts'
  multipass exec "${node}" -- sudo install -o root -g vault -m 0640 /tmp/vault.hcl /etc/vault.d/vault.hcl
  multipass exec "${node}" -- sudo install -o root -g root -m 0644 /tmp/vault.service /etc/systemd/system/vault.service
  multipass exec "${node}" -- sudo install -o vault -g vault -m 0644 /tmp/ca.crt /opt/vault/tls/ca.crt
  multipass exec "${node}" -- sudo install -o vault -g vault -m 0644 /tmp/server.crt /opt/vault/tls/server.crt
  multipass exec "${node}" -- sudo install -o vault -g vault -m 0600 /tmp/server.key /opt/vault/tls/server.key
  multipass exec "${node}" -- sudo rm -f /tmp/vault-lab-hosts /tmp/vault.hcl /tmp/vault.service /tmp/ca.crt /tmp/server.crt /tmp/server.key

  multipass exec "${node}" -- sudo test -r /opt/vault/vault.hclic ||
    die "License is absent on ${node}. Run 'make license' first."
  multipass exec "${node}" -- sudo /usr/local/bin/vault server -config=/etc/vault.d/vault.hcl -verify-only
  multipass exec "${node}" -- sudo systemctl daemon-reload
  multipass exec "${node}" -- sudo systemctl enable --now vault
  multipass exec "${node}" -- sudo systemctl is-active --quiet vault || {
    multipass exec "${node}" -- sudo journalctl -u vault --no-pager -n 50
    die "Vault failed to start on ${node}."
  }
done

info "Vault configuration and systemd service are active on all nodes."
