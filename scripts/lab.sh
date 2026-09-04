#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)"

run_phase() {
  printf '\n==> LAB PHASE: %s\n' "$1"
  shift
  "$@"
}

cd "${ROOT_DIR}"
run_phase "static prerequisites" "${SCRIPT_DIR}/check.sh"
run_phase "pinned Ansible collections" "${SCRIPT_DIR}/ansible-deps.sh"
run_phase "dedicated controller SSH key" "${SCRIPT_DIR}/ansible-ssh.sh" prepare
run_phase "Terraform deployment" make deployment
run_phase "in-place SSH authorization and host trust" "${SCRIPT_DIR}/ansible-ssh.sh" all
run_phase "Terraform-triggered Ansible convergence" "${SCRIPT_DIR}/ansible-run.sh" apply
run_phase "Vault cluster validation" "${SCRIPT_DIR}/validate.sh"
run_phase "Vault platform Terraform" "${SCRIPT_DIR}/platform.sh" apply
run_phase "clean Ansible orchestration plan" "${SCRIPT_DIR}/ansible-run.sh" validate
run_phase "clean Vault platform plan" "${SCRIPT_DIR}/platform.sh" validate

printf '\n==> PASS: the complete Vault lab converged through make lab.\n'
