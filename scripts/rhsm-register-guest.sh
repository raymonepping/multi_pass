#!/usr/bin/env bash

# Runs as root inside one lab guest. Do not enable shell tracing in this file.
set -euo pipefail

credentials_file="${1:-}"
[[ -n "${credentials_file}" && -f "${credentials_file}" ]] || {
  printf 'RHSM credential file is missing.\n' >&2
  exit 1
}

cleanup() {
  if command -v shred >/dev/null 2>&1; then
    shred -u "${credentials_file}" 2>/dev/null || rm -f "${credentials_file}"
  else
    rm -f "${credentials_file}"
  fi
}
trap cleanup EXIT HUP INT TERM

IFS= read -r rhsm_org <"${credentials_file}"
IFS= read -r rhsm_activation_key < <(sed -n '2p' "${credentials_file}")
[[ -n "${rhsm_org}" && -n "${rhsm_activation_key}" ]] || {
  printf 'RHSM credentials are incomplete.\n' >&2
  exit 1
}

subscription-manager register \
  --org="${rhsm_org}" \
  --activationkey="${rhsm_activation_key}"

unset rhsm_activation_key rhsm_org
