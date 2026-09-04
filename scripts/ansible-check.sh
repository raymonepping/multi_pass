#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ansible-env.sh
source "${SCRIPT_DIR}/ansible-env.sh"

require_cmd ansible-playbook
ansible-playbook --syntax-check "${ROOT_DIR}/ansible/terraform.yml" \
  --extra-vars '{"vault_nodes_json":"{}","ansible_private_key_file":"/dev/null","ansible_known_hosts_file":"/dev/null","automation_digest":"syntax-check"}'

if [[ -f "${INFRA_DIR}/terraform.tfstate" && -s "${SECRETS_DIR}/ansible/id_ed25519" && -s "${SECRETS_DIR}/ansible/known_hosts" ]]; then
  topology="$(terraform -chdir="${INFRA_DIR}" output -json ansible_nodes)"
  ansible-playbook "${ROOT_DIR}/ansible/provider-smoke.yml" \
    --extra-vars "$(jq -cn \
      --arg nodes "${topology}" \
      --arg private_key "${SECRETS_DIR}/ansible/id_ed25519" \
      --arg known_hosts "${SECRETS_DIR}/ansible/known_hosts" \
      '{vault_nodes_json: $nodes, ansible_private_key_file: $private_key, ansible_known_hosts_file: $known_hosts}')"
fi

info "Ansible syntax and Terraform-to-Ansible handoff checks passed."
