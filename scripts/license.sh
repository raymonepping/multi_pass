#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_managed_nodes
[[ -n "${VAULT_LICENSE_FILE:-}" ]] || die "Set VAULT_LICENSE_FILE to your Vault Enterprise .hclic path, then rerun 'make license'."
[[ -f "${VAULT_LICENSE_FILE}" ]] || die "License file does not exist: ${VAULT_LICENSE_FILE}"
[[ ! -L "${VAULT_LICENSE_FILE}" ]] || die "License input must be a regular file, not a symbolic link."

for node in "${NODES[@]}"; do
  vault_group_exists="$(multipass exec "${node}" -- sh -c \
    'if getent group vault >/dev/null 2>&1; then printf yes; else printf no; fi')"
  [[ "${vault_group_exists}" == "yes" ]] ||
    die "The vault service account is absent on ${node}. Run 'make install' before installing the license."
done

temporary_license_node=""
cleanup() {
  if [[ -n "${temporary_license_node}" ]]; then
    multipass exec "${temporary_license_node}" -- sudo rm -f /tmp/vault.hclic >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT HUP INT TERM

for node in "${NODES[@]}"; do
  info "Installing the supplied license on ${node} (contents suppressed)"
  temporary_license_node="${node}"
  multipass transfer "${VAULT_LICENSE_FILE}" "${node}:/tmp/vault.hclic"
  multipass exec "${node}" -- sudo install -o root -g vault -m 0640 /tmp/vault.hclic /opt/vault/vault.hclic
  multipass exec "${node}" -- sudo rm -f /tmp/vault.hclic
  temporary_license_node=""
done

info "The license is installed on all nodes."
