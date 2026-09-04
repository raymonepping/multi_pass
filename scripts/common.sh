#!/usr/bin/env bash
# shellcheck disable=SC2034

set -euo pipefail

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${ROOT_DIR}/terraform/infra"
PLATFORM_DIR="${ROOT_DIR}/terraform/platform"
SECRETS_DIR="${ROOT_DIR}/.secrets"
CACHE_DIR="${ROOT_DIR}/.cache"
TLS_DIR="${SECRETS_DIR}/tls"
INIT_FILE="${SECRETS_DIR}/vault-init.json"
PLATFORM_TOKEN_FILE="${SECRETS_DIR}/platform-token"
NODES=(vault-1 vault-2 vault-3)

VAULT_VERSION="${VAULT_VERSION:-2.1.0+ent}"
VAULT_ARCHIVE_SHA256="${VAULT_ARCHIVE_SHA256:-a0fbfb3fb07e5c4574f07062338f8fb10b4464c0622e3cc9b3b030d3c9afc2da}"
KEY_SHARES="${KEY_SHARES:-3}"
KEY_THRESHOLD="${KEY_THRESHOLD:-2}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

prepare_local_dirs() {
  umask 077
  mkdir -p "${SECRETS_DIR}" "${CACHE_DIR}"
  chmod 700 "${SECRETS_DIR}" "${CACHE_DIR}"
}

require_infra_state() {
  [[ -f "${INFRA_DIR}/terraform.tfstate" ]] || die "Infrastructure state is absent. Run 'make infra' first."
}

node_ip() {
  local node="$1"
  require_infra_state
  terraform -chdir="${INFRA_DIR}" output -json node_ipv4 | jq -er --arg node "${node}" '.[$node]'
}

require_managed_nodes() {
  local node actual
  require_infra_state
  for node in "${NODES[@]}"; do
    actual="$(terraform -chdir="${INFRA_DIR}" output -json node_names | jq -er --arg node "${node}" 'index($node) // empty')"
    [[ -n "${actual}" ]] || die "${node} is not present in Terraform output."
    multipass info "${node}" >/dev/null 2>&1 || die "Terraform-managed instance ${node} is unavailable."
  done
}

vault_cli() {
  local node="$1"
  shift
  VAULT_ADDR="https://$(node_ip "${node}"):8200" \
  VAULT_CACERT="${TLS_DIR}/ca.crt" \
    vault "$@"
}

root_token() {
  [[ -f "${INIT_FILE}" ]] || die "Vault initialization file is absent. Run 'make bootstrap' first."
  jq -er '.root_token' "${INIT_FILE}"
}

run_with_root_token() {
  local node="$1"
  shift
  local token
  token="$(root_token)"
  VAULT_ADDR="https://$(node_ip "${node}"):8200" \
  VAULT_CACERT="${TLS_DIR}/ca.crt" \
  VAULT_TOKEN="${token}" \
    vault "$@"
}
