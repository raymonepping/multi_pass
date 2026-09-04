#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd terraform
require_cmd multipass
require_cmd jq
require_managed_nodes

for node in "${NODES[@]}"; do
  info "Validating ${node} ($(node_ip "${node}"))"
  cloud_init_status="$(multipass exec "${node}" -- sudo cloud-init status --long)"
  rg -q '^status: done$' <<<"${cloud_init_status}" || die "cloud-init is not done on ${node}."
  rg -q '^errors: \[\]$' <<<"${cloud_init_status}" || die "cloud-init reported errors on ${node}."
  [[ "$(multipass exec "${node}" -- uname -m)" == "aarch64" ]] || die "${node} is not ARM64."
  multipass exec "${node}" -- grep -q '^PLATFORM_ID="platform:el9"' /etc/os-release
  [[ "$(multipass exec "${node}" -- getenforce)" == "Enforcing" ]] || die "SELinux is not enforcing on ${node}."
  multipass exec "${node}" -- test -x /usr/bin/firewall-cmd ||
    die "firewalld is missing on ${node}; use a RHEL image that includes it."
  multipass exec "${node}" -- df -h /
done

info "All Terraform-managed VMs passed validation."
