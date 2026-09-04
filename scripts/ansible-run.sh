#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ansible-env.sh
source "${SCRIPT_DIR}/ansible-env.sh"

require_cmd terraform
require_cmd ansible-playbook
require_infra_state
[[ -s "${SECRETS_DIR}/ansible/id_ed25519" ]] || die "Dedicated Ansible SSH key is absent. Run 'make ansible-ssh'."
[[ -s "${SECRETS_DIR}/ansible/known_hosts" ]] || die "Ansible known_hosts is absent. Run 'make ansible-ssh'."

action="${1:-}"
terraform -chdir="${ROOT_DIR}/terraform/ansible" init
terraform -chdir="${ROOT_DIR}/terraform/ansible" validate

case "${action}" in
plan)
  terraform -chdir="${ROOT_DIR}/terraform/ansible" plan
  ;;
apply)
  if terraform -chdir="${ROOT_DIR}/terraform/ansible" state show ansible_playbook.vault_lab >/dev/null 2>&1; then
    terraform -chdir="${ROOT_DIR}/terraform/ansible" apply \
      -replace=ansible_playbook.vault_lab -auto-approve
  else
    terraform -chdir="${ROOT_DIR}/terraform/ansible" apply -auto-approve
  fi
  ;;
validate)
  set +e
  terraform -chdir="${ROOT_DIR}/terraform/ansible" plan -detailed-exitcode
  plan_rc=$?
  set -e
  [[ ${plan_rc} -eq 0 ]] || {
    [[ ${plan_rc} -eq 2 ]] && die "Ansible orchestration drift detected: apply 'make ansible-converge'."
    die "Ansible orchestration plan failed."
  }
  info "Ansible orchestration state is clean."
  ;;
*) die "Usage: $0 {plan|apply|validate}" ;;
esac
