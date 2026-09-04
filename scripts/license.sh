#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_managed_nodes
prepare_local_dirs

temporary_license_node=""
temporary_local_license=""
cleanup() {
  if [[ -n "${temporary_license_node}" ]]; then
    multipass exec "${temporary_license_node}" -- sudo rm -f /tmp/vault.hclic >/dev/null 2>&1 || true
  fi
  if [[ -n "${temporary_local_license}" ]]; then
    rm -f "${temporary_local_license}"
  fi
}
trap cleanup EXIT HUP INT TERM

configured_license_inputs=0
[[ -n "${VAULT_LICENSE_FILE:-}" ]] && configured_license_inputs=$((configured_license_inputs + 1))
[[ -n "${VAULT_LICENSE_ENV_FILE:-}" ]] && configured_license_inputs=$((configured_license_inputs + 1))
[[ -n "${VAULT_LICENSE:-}" ]] && configured_license_inputs=$((configured_license_inputs + 1))
[[ ${configured_license_inputs} -eq 1 ]] || \
  die "Configure exactly one of VAULT_LICENSE_FILE, VAULT_LICENSE_ENV_FILE, or VAULT_LICENSE."

if [[ -n "${VAULT_LICENSE_FILE:-}" ]]; then
  [[ -f "${VAULT_LICENSE_FILE}" ]] || die "License file does not exist: ${VAULT_LICENSE_FILE}"
  [[ ! -L "${VAULT_LICENSE_FILE}" ]] || die "License input must be a regular file, not a symbolic link."
  license_source="${VAULT_LICENSE_FILE}"
else
  temporary_local_license="$(mktemp "${SECRETS_DIR}/vault-license.XXXXXX")"
  chmod 600 "${temporary_local_license}"
  if [[ -n "${VAULT_LICENSE_ENV_FILE:-}" ]]; then
    [[ -f "${VAULT_LICENSE_ENV_FILE}" ]] || die "License environment file does not exist: ${VAULT_LICENSE_ENV_FILE}"
    awk '
      /^[[:space:]]*(export[[:space:]]+)?VAULT_LICENSE=/ {
        value=$0
        sub(/^[[:space:]]*(export[[:space:]]+)?VAULT_LICENSE=/, "", value)
        sub(/\r$/, "", value)
        if ((substr(value, 1, 1) == "\"" && substr(value, length(value), 1) == "\"") ||
            (substr(value, 1, 1) == "\047" && substr(value, length(value), 1) == "\047")) {
          value=substr(value, 2, length(value)-2)
        }
        print value
        found=1
        exit
      }
      END { if (!found) exit 1 }
    ' "${VAULT_LICENSE_ENV_FILE}" > "${temporary_local_license}" || \
      die "VAULT_LICENSE is absent from ${VAULT_LICENSE_ENV_FILE}."
  else
    printf '%s\n' "${VAULT_LICENSE}" > "${temporary_local_license}"
  fi
  license_source="${temporary_local_license}"
fi

license_prefix="$(LC_ALL=C head -c 2 "${license_source}")"
[[ "${license_prefix}" =~ ^0[0-9]$ ]] || \
  die "The selected input is not a raw HashiCorp license. Expected a version prefix such as 02; check for a placeholder, wrapper, or altered file."

for node in "${NODES[@]}"; do
  vault_group_exists="$(multipass exec "${node}" -- sh -c \
    'if getent group vault >/dev/null 2>&1; then printf yes; else printf no; fi')"
  [[ "${vault_group_exists}" == "yes" ]] ||
    die "The vault service account is absent on ${node}. Run 'make install' before installing the license."
done

for node in "${NODES[@]}"; do
  info "Installing the supplied license on ${node} (contents suppressed)"
  temporary_license_node="${node}"
  multipass transfer "${license_source}" "${node}:/tmp/vault.hclic"
  multipass exec "${node}" -- sudo install -o root -g vault -m 0640 /tmp/vault.hclic /opt/vault/vault.hclic
  multipass exec "${node}" -- sudo rm -f /tmp/vault.hclic
  temporary_license_node=""
done

info "The license is installed on all nodes."
