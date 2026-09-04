#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ansible-env.sh
source "${SCRIPT_DIR}/ansible-env.sh"

require_cmd ansible-inventory
require_infra_state

cd "${INFRA_DIR}"
ansible-inventory -i "${ROOT_DIR}/ansible/inventory/terraform_provider.yml" --graph --vars
