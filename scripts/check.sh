#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

for command_name in terraform multipass ansible-playbook ansible-galaxy jq openssl curl unzip shasum file ssh-keygen ssh-keyscan; do
  require_cmd "${command_name}"
done

image_path="${TF_VAR_image_path:-/Users/Shared/rhel-9.8-aarch64-kvm.qcow2}"
[[ -f "${image_path}" ]] || die "RHEL image not found: ${image_path}"

terraform version | head -n 1
multipass version

terraform -chdir="${INFRA_DIR}" fmt -check -recursive
terraform -chdir="${ROOT_DIR}/terraform/ansible" fmt -check -recursive
terraform -chdir="${PLATFORM_DIR}" fmt -check -recursive

ansible_core_version="$(ANSIBLE_LOCAL_TEMP="${TMPDIR:-/tmp}/vault-lab-ansible-tmp" ansible --version | awk 'NR == 1 { gsub(/[][]/, "", $3); print $3 }')"
python_version="$(python3 -c 'import platform; print(platform.python_version())')"
info "Ansible Core ${ansible_core_version}; controller Python ${python_version}"

if git -C "${ROOT_DIR}" ls-files | rg -q '(^|/)(\.secrets|terraform\.tfstate|vault-init)|\.hclic$|\.(key|pem)$'; then
  die "A sensitive or generated file appears to be tracked by Git."
fi

if [[ -n "${VAULT_LICENSE_FILE:-}" ]]; then
  [[ -f "${VAULT_LICENSE_FILE}" ]] || die "VAULT_LICENSE_FILE does not exist: ${VAULT_LICENSE_FILE}"
  info "Vault license found: ${VAULT_LICENSE_FILE}"
else
  info "VAULT_LICENSE_FILE is not set; infrastructure can proceed, but 'make license' will stop."
fi

if [[ -n "${TF_LICENSE_PATH:-}" ]]; then
  [[ -f "${TF_LICENSE_PATH}" ]] || die "TF_LICENSE_PATH does not exist: ${TF_LICENSE_PATH}"
  info "Terraform license found: ${TF_LICENSE_PATH}"
else
  info "TF_LICENSE_PATH is not set; Terraform Enterprise features will be unavailable."
fi

if [[ -n "${RHSM_ORG:-}" || -n "${RHSM_ACTIVATION_KEY:-}" ]]; then
  [[ -n "${RHSM_ORG:-}" && -n "${RHSM_ACTIVATION_KEY:-}" ]] ||
    die "Set both RHSM_ORG and RHSM_ACTIVATION_KEY, or neither."
  info "RHSM activation-key inputs are configured (values suppressed)."
else
  info "RHSM inputs are not set; already-prepared guests need no RHSM credentials."
fi

info "Static and host prerequisite checks passed."
