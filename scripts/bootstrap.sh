#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd vault
require_cmd jq
require_managed_nodes
prepare_local_dirs
[[ -f "${TLS_DIR}/ca.crt" ]] || die "TLS CA is absent. Run 'make configure' first."

status_json() {
  local node="$1"
  local output rc
  set +e
  output="$(vault_cli "${node}" status -format=json 2>/dev/null)"
  rc=$?
  set -e
  [[ ${rc} -eq 0 || ${rc} -eq 2 ]] || die "Cannot obtain Vault status from ${node}."
  printf '%s' "${output}"
}

unseal_node() {
  local node="$1" status key_index key tls_valid
  status="$(status_json "${node}")"
  if [[ "$(jq -r '.sealed' <<<"${status}")" == "false" ]]; then
    info "${node} is already unsealed."
    return
  fi

  tls_valid="no"
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    tls_valid="$(multipass exec "${node}" -- sh -c \
      'if sudo openssl verify -CAfile /opt/vault/tls/ca.crt /opt/vault/tls/server.crt >/dev/null 2>&1; then printf yes; else printf no; fi')"
    [[ "${tls_valid}" == "yes" ]] && break
    sleep 2
  done
  [[ "${tls_valid}" == "yes" ]] || die "TLS certificate is not currently valid according to ${node}'s clock."

  for _ in 1 2; do
    for ((key_index = 0; key_index < KEY_THRESHOLD; key_index++)); do
      key="$(jq -er ".unseal_keys_b64[${key_index}]" "${INIT_FILE}")"
      vault_cli "${node}" operator unseal "${key}" >/dev/null
    done
    sleep 3
    if [[ "$(jq -r '.sealed' <<<"$(status_json "${node}")")" == "false" ]]; then
      info "${node} is unsealed."
      return
    fi
    info "${node} resealed during startup; retrying once after TLS/cluster stabilization."
    sleep 5
  done
  die "Failed to keep ${node} unsealed. Inspect its Vault service journal."
}

leader_status="$(status_json vault-1)"
leader_initialized="$(jq -r '.initialized' <<<"${leader_status}")"

if [[ "${leader_initialized}" == "false" ]]; then
  [[ ! -e "${INIT_FILE}" ]] || die "Local init file exists but vault-1 reports uninitialized. Refusing to overwrite recovery material."
  info "Initializing vault-1 with ${KEY_SHARES} shares and threshold ${KEY_THRESHOLD}"
  temporary_init="$(mktemp "${SECRETS_DIR}/vault-init.XXXXXX")"
  vault_cli vault-1 operator init \
    -key-shares="${KEY_SHARES}" \
    -key-threshold="${KEY_THRESHOLD}" \
    -format=json >"${temporary_init}"
  chmod 600 "${temporary_init}"
  mv "${temporary_init}" "${INIT_FILE}"
else
  [[ -f "${INIT_FILE}" ]] || die "vault-1 is initialized but ${INIT_FILE} is absent. Restore it before continuing."
  info "vault-1 is already initialized; preserving existing recovery material."
fi

unseal_node vault-1

for node in vault-2 vault-3; do
  follower_status="$(status_json "${node}")"
  if [[ "$(jq -r '.initialized' <<<"${follower_status}")" == "false" ]]; then
    info "Joining ${node} to vault-1's Raft cluster"
    ca_content="$(<"${TLS_DIR}/ca.crt")"
    vault_cli "${node}" operator raft join \
      -leader-ca-cert="${ca_content}" \
      "https://$(node_ip vault-1):8200" >/dev/null
  else
    info "${node} is already initialized/joined."
  fi
  unseal_node "${node}"
done

token="$(root_token)"
VAULT_ADDR="https://$(node_ip vault-1):8200" VAULT_CACERT="${TLS_DIR}/ca.crt" VAULT_TOKEN="${token}" \
  vault policy write lab-platform-admin "${ROOT_DIR}/policies/platform-admin.hcl" >/dev/null

create_platform_token=true
if [[ -s "${PLATFORM_TOKEN_FILE}" ]]; then
  existing_platform_token="$(<"${PLATFORM_TOKEN_FILE}")"
  if VAULT_ADDR="https://$(node_ip vault-1):8200" VAULT_CACERT="${TLS_DIR}/ca.crt" VAULT_TOKEN="${existing_platform_token}" \
    vault token lookup >/dev/null 2>&1; then
    create_platform_token=false
    info "Existing platform token remains valid."
  fi
fi

if [[ "${create_platform_token}" == true ]]; then
  info "Creating a renewable lab platform token"
  VAULT_ADDR="https://$(node_ip vault-1):8200" VAULT_CACERT="${TLS_DIR}/ca.crt" VAULT_TOKEN="${token}" \
    vault token create -orphan -period=24h -policy=lab-platform-admin -field=token >"${PLATFORM_TOKEN_FILE}"
  chmod 600 "${PLATFORM_TOKEN_FILE}"
fi

peer_count="$(run_with_root_token vault-1 operator raft list-peers -format=json | jq '.data.config.servers | length')"
[[ "${peer_count}" -eq 3 ]] || die "Expected three Raft peers, found ${peer_count}."
info "Vault cluster bootstrap completed with three Raft peers."
