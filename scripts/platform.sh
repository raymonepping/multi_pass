#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd terraform
require_cmd vault
require_managed_nodes
[[ -s "${PLATFORM_TOKEN_FILE}" ]] || die "Platform token is absent. Run 'make bootstrap' first."
[[ -f "${TLS_DIR}/ca.crt" ]] || die "TLS CA is absent."

action="${1:-}"
case "${action}" in
plan | apply | validate) ;;
*) die "Usage: $0 {plan|apply|validate}" ;;
esac

VAULT_ADDR="https://$(node_ip vault-1):8200"
export VAULT_CACERT="${TLS_DIR}/ca.crt"
VAULT_TOKEN="$(<"${PLATFORM_TOKEN_FILE}")"
export VAULT_ADDR VAULT_TOKEN

terraform -chdir="${PLATFORM_DIR}" init

case "${action}" in
plan)
  terraform -chdir="${PLATFORM_DIR}" validate
  terraform -chdir="${PLATFORM_DIR}" plan
  ;;
apply)
  terraform -chdir="${PLATFORM_DIR}" validate
  terraform -chdir="${PLATFORM_DIR}" apply
  ;;
validate)
  terraform -chdir="${PLATFORM_DIR}" validate
  set +e
  terraform -chdir="${PLATFORM_DIR}" plan -detailed-exitcode
  plan_rc=$?
  set -e
  [[ ${plan_rc} -eq 0 ]] || {
    [[ ${plan_rc} -eq 2 ]] && die "Platform drift detected: Terraform plan is not clean."
    die "Platform plan failed."
  }
  info "Platform validation passed and the Terraform plan is clean."
  ;;
esac
