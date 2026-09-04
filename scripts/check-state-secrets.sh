#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd rg
require_cmd jq

state_files=()
while IFS= read -r state_file; do
  state_files+=("${state_file}")
done < <(find "${ROOT_DIR}/terraform" -type f \
  \( -name 'terraform.tfstate' -o -name 'terraform.tfstate.backup' \) -print)
[[ ${#state_files[@]} -gt 0 ]] || {
  info "No Terraform state files exist yet; secret-state check skipped."
  exit 0
}

pattern_file="$(mktemp "${TMPDIR:-/tmp}/vault-state-secret-patterns.XXXXXX")"
chmod 600 "${pattern_file}"
trap 'rm -f "${pattern_file}"' EXIT HUP INT TERM

if [[ -s "${INIT_FILE}" ]]; then
  jq -r '.root_token, .unseal_keys_b64[]' "${INIT_FILE}" >>"${pattern_file}"
fi
if [[ -s "${PLATFORM_TOKEN_FILE}" ]]; then
  tr -d '\r\n' <"${PLATFORM_TOKEN_FILE}" >>"${pattern_file}"
  printf '\n' >>"${pattern_file}"
fi
if [[ -s "${VAULT_LICENSE_FILE}" ]]; then
  tr -d '\r\n' <"${VAULT_LICENSE_FILE}" >>"${pattern_file}"
  printf '\n' >>"${pattern_file}"
fi
if [[ -s "${SECRETS_DIR}/ansible/id_ed25519" ]]; then
  awk 'NR == 2 { print; exit }' "${SECRETS_DIR}/ansible/id_ed25519" >>"${pattern_file}"
fi

if [[ -s "${pattern_file}" ]] && rg -Fq -f "${pattern_file}" "${state_files[@]}"; then
  die "Sensitive material was found in Terraform state. No value was printed."
fi

info "Terraform state contains none of the known license, token, unseal, or private-key values."
