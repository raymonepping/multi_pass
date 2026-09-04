#!/usr/bin/env bash

# Shared controller environment for direct Ansible commands and the Terraform
# Ansible provider. This file contains paths only, never credentials.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

prepare_local_dirs
mkdir -p "${CACHE_DIR}/ansible/tmp" "${CACHE_DIR}/ansible/collections"
chmod 700 "${CACHE_DIR}/ansible" "${CACHE_DIR}/ansible/tmp" "${CACHE_DIR}/ansible/collections"

export ANSIBLE_CONFIG="${ROOT_DIR}/ansible.cfg"
export ANSIBLE_LOCAL_TEMP="${CACHE_DIR}/ansible/tmp"
export ANSIBLE_COLLECTIONS_PATH="${CACHE_DIR}/ansible/collections"
export ANSIBLE_GALAXY_TOKEN_PATH="${CACHE_DIR}/ansible/galaxy_token"
export ANSIBLE_NOCOLOR=1
