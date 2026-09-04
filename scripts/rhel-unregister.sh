#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd terraform
require_cmd multipass
require_managed_nodes

[[ "${CONFIRM_RHSM_UNREGISTER:-}" == "yes" ]] ||
  die "This removes three systems from Red Hat Subscription Management. Rerun with CONFIRM_RHSM_UNREGISTER=yes."

for node in "${NODES[@]}"; do
  rhsm_registered="$(multipass exec "${node}" -- sh -c \
    'if sudo subscription-manager identity >/dev/null 2>&1; then printf yes; else printf no; fi')"
  if [[ "${rhsm_registered}" == "yes" ]]; then
    info "Unregistering ${node} from Red Hat Subscription Management"
    multipass exec "${node}" -- sudo subscription-manager unregister
    rhsm_registered="$(multipass exec "${node}" -- sh -c \
      'if sudo subscription-manager identity >/dev/null 2>&1; then printf yes; else printf no; fi')"
    [[ "${rhsm_registered}" == "no" ]] || die "${node} still reports a registered identity."
  else
    info "${node} is already unregistered."
  fi
done

info "All Terraform-managed nodes are unregistered."
