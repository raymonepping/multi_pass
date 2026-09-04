#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd vault
require_cmd jq
require_managed_nodes
[[ -f "${TLS_DIR}/ca.crt" ]] || die "TLS CA is absent."
[[ -f "${INIT_FILE}" ]] || die "Initialization material is absent."

leader_count=0
standby_count=0

for node in "${NODES[@]}"; do
  info "Validating ${node}"
  multipass exec "${node}" -- sudo systemctl is-active --quiet vault
  multipass exec "${node}" -- test "$(multipass exec "${node}" -- getenforce)" = "Enforcing"
  [[ -z "$(multipass exec "${node}" -- sudo swapon --show --noheadings)" ]] || die "Swap is active on ${node}."
  ports="$(multipass exec "${node}" -- sudo firewall-cmd --list-ports)"
  rg -qw '8200/tcp' <<<"${ports}" || die "TCP 8200 is not open on ${node}."
  rg -qw '8201/tcp' <<<"${ports}" || die "TCP 8201 is not open on ${node}."

  set +e
  status="$(vault_cli "${node}" status -format=json 2>/dev/null)"
  status_rc=$?
  set -e
  [[ ${status_rc} -eq 0 ]] || die "Vault on ${node} is unavailable or sealed."
  [[ "$(jq -r '.initialized' <<<"${status}")" == "true" ]] || die "${node} is uninitialized."
  [[ "$(jq -r '.sealed' <<<"${status}")" == "false" ]] || die "${node} is sealed."
  case "$(jq -r '.ha_mode' <<<"${status}")" in
  active) leader_count=$((leader_count + 1)) ;;
  standby | performance_standby) standby_count=$((standby_count + 1)) ;;
  *) die "Unexpected HA mode on ${node}: $(jq -r '.ha_mode' <<<"${status}")" ;;
  esac
  jq '{initialized, sealed, version, cluster_name, ha_enabled, ha_mode}' <<<"${status}"
done

[[ ${leader_count} -eq 1 && ${standby_count} -eq 2 ]] ||
  die "Expected one active and two standby nodes; found ${leader_count} active and ${standby_count} standby."

peers="$(run_with_root_token vault-1 operator raft list-peers -format=json)"
[[ "$(jq '[.data.config.servers[] | select(.voter == true)] | length' <<<"${peers}")" -eq 3 ]] ||
  die "Raft does not contain three voters."
jq '.data.config.servers | map({node_id, address, leader, voter})' <<<"${peers}"

run_with_root_token vault-1 license get -format=json | jq '{autoloading_used: .data.autoloading_used, termination_time: .data.termination_time}'
info "Cluster validation passed: one active, two standby, three voters."
