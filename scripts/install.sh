#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd curl
require_cmd shasum
require_cmd unzip
require_cmd file
require_cmd multipass
require_managed_nodes
prepare_local_dirs

archive="vault_${VAULT_VERSION}_linux_arm64.zip"
archive_path="${CACHE_DIR}/${archive}"
release_url="https://releases.hashicorp.com/vault/${VAULT_VERSION}/${archive}"

if [[ ! -f "${archive_path}" ]] || [[ "$(shasum -a 256 "${archive_path}" | awk '{print $1}')" != "${VAULT_ARCHIVE_SHA256}" ]]; then
  info "Downloading Vault Enterprise ${VAULT_VERSION} for Linux ARM64"
  curl --fail --location --silent --show-error "${release_url}" --output "${archive_path}"
fi

actual_sha="$(shasum -a 256 "${archive_path}" | awk '{print $1}')"
[[ "${actual_sha}" == "${VAULT_ARCHIVE_SHA256}" ]] || die "Vault archive checksum mismatch."
info "Vault archive SHA-256 verified."

rm -f "${CACHE_DIR}/vault"
unzip -oq "${archive_path}" vault -d "${CACHE_DIR}"
file "${CACHE_DIR}/vault" | rg -q 'ELF 64-bit.*(ARM aarch64|ARM64)' ||
  die "Downloaded Vault artifact is not a Linux ARM64 executable."

for node in "${NODES[@]}"; do
  info "Installing Vault on ${node}"
  multipass transfer "${CACHE_DIR}/vault" "${node}:/tmp/vault"
  multipass transfer "${SCRIPT_DIR}/install-vault-guest.sh" "${node}:/tmp/install-vault-guest.sh"
  installed_version="$(multipass exec "${node}" -- sudo /bin/bash /tmp/install-vault-guest.sh)"
  rg -Fq "${VAULT_VERSION}" <<<"${installed_version}" || die "Installed Vault version is incorrect on ${node}."
  printf '%s\n' "${installed_version}"
done

info "Vault Enterprise is installed on all nodes."
