#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ansible-env.sh
source "${SCRIPT_DIR}/ansible-env.sh"

require_cmd ansible-playbook
require_cmd ansible-inventory

ansible-playbook --syntax-check "${ROOT_DIR}/ansible/terraform.yml" \
  --extra-vars '{"vault_nodes_json":"{}","ansible_private_key_file":"/dev/null","ansible_known_hosts_file":"/dev/null","automation_digest":"syntax-check"}'

if [[ -f "${INFRA_DIR}/terraform.tfstate" ]]; then
  cd "${INFRA_DIR}"
  inventory_json="$(ansible-inventory -i "${ROOT_DIR}/ansible/inventory/terraform_provider.yml" --list)"
  for node in "${NODES[@]}"; do
    jq -e --arg node "${node}" '._meta.hostvars[$node].ansible_host | length > 0' <<<"${inventory_json}" >/dev/null ||
      die "Provider-backed inventory is missing ${node}."
  done
fi

info "Ansible syntax and provider-backed inventory checks passed."
