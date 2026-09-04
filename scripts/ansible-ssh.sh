#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd ssh-keygen
require_cmd ssh-keyscan
require_cmd multipass

SSH_DIR="${SECRETS_DIR}/ansible"
PRIVATE_KEY="${SSH_DIR}/id_ed25519"
PUBLIC_KEY="${PRIVATE_KEY}.pub"
KNOWN_HOSTS="${SSH_DIR}/known_hosts"
scan_file=""

cleanup() {
  if [[ -n "${scan_file}" && -f "${scan_file}" ]]; then
    rm -f "${scan_file}"
  fi
}
trap cleanup EXIT HUP INT TERM

prepare_key() {
  prepare_local_dirs
  mkdir -p "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"
  if [[ ! -f "${PRIVATE_KEY}" || ! -f "${PUBLIC_KEY}" ]]; then
    [[ ! -e "${PRIVATE_KEY}" && ! -e "${PUBLIC_KEY}" ]] ||
      die "The dedicated SSH key pair is incomplete under ${SSH_DIR}; repair or remove both files explicitly."
    info "Generating the dedicated Vault lab Ansible SSH identity"
    ssh-keygen -q -t ed25519 -N '' -C 'vault-multipass-lab' -f "${PRIVATE_KEY}"
  fi
  chmod 600 "${PRIVATE_KEY}"
  chmod 644 "${PUBLIC_KEY}"
  public_key="$(<"${PUBLIC_KEY}")"
  [[ "${public_key}" =~ ^ssh-ed25519[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]] ||
    die "The dedicated public key has an unexpected format."
}

node_has_key() {
  local node="$1"
  multipass transfer "${PUBLIC_KEY}" "${node}:/tmp/vault-lab-ansible.pub" >/dev/null
  if multipass exec "${node}" -- sh -c \
    'grep -Fqx "$(cat /tmp/vault-lab-ansible.pub)" /home/ubuntu/.ssh/authorized_keys 2>/dev/null'; then
    multipass exec "${node}" -- rm -f /tmp/vault-lab-ansible.pub
    return 0
  fi
  multipass exec "${node}" -- rm -f /tmp/vault-lab-ansible.pub
  return 1
}

migrate_existing_nodes() {
  local node answer
  local -a missing_nodes=()
  require_managed_nodes
  for node in "${NODES[@]}"; do
    node_has_key "${node}" || missing_nodes+=("${node}")
  done
  if [[ ${#missing_nodes[@]} -eq 0 ]]; then
    info "The dedicated Ansible public key is already authorized on all managed nodes."
    return
  fi

  if [[ "${CONFIRM_ANSIBLE_SSH_MIGRATION:-}" != "yes" ]]; then
    [[ -t 0 ]] || die "Existing nodes need the dedicated public key. Rerun with CONFIRM_ANSIBLE_SSH_MIGRATION=yes."
    printf 'Authorize the dedicated lab key on %s? [y/N] ' "${missing_nodes[*]}" >&2
    read -r answer
    [[ "${answer}" == "y" || "${answer}" == "Y" ]] || die "SSH key migration cancelled."
  fi

  for node in "${missing_nodes[@]}"; do
    info "Authorizing the dedicated Ansible public key on ${node}"
    multipass transfer "${PUBLIC_KEY}" "${node}:/tmp/vault-lab-ansible.pub"
    multipass exec "${node}" -- sudo sh -c '
      install -d -o ubuntu -g ubuntu -m 0700 /home/ubuntu/.ssh
      touch /home/ubuntu/.ssh/authorized_keys
      chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
      chmod 0600 /home/ubuntu/.ssh/authorized_keys
      key="$(cat /tmp/vault-lab-ansible.pub)"
      grep -Fqx "$key" /home/ubuntu/.ssh/authorized_keys || printf "%s\n" "$key" >> /home/ubuntu/.ssh/authorized_keys
      rm -f /tmp/vault-lab-ansible.pub
    '
  done
}

trust_hosts() {
  local node ip existing_key scanned_key answer
  scan_file="$(mktemp "${SSH_DIR}/known-hosts-scan.XXXXXX")"
  touch "${KNOWN_HOSTS}"
  chmod 600 "${KNOWN_HOSTS}"

  for node in "${NODES[@]}"; do
    ip="$(node_ip "${node}")"
    : >"${scan_file}"
    ssh-keyscan -T 10 -t ed25519 "${ip}" >"${scan_file}" 2>/dev/null ||
      die "Cannot obtain the SSH host key for ${node} (${ip})."
    scanned_key="$(awk 'NF >= 3 { print $2 " " $3; exit }' "${scan_file}")"
    [[ -n "${scanned_key}" ]] || die "SSH host-key scan returned no ED25519 key for ${node}."

    existing_key="$(ssh-keygen -F "${ip}" -f "${KNOWN_HOSTS}" 2>/dev/null | awk 'NF >= 3 && $1 !~ /^#/ { print $2 " " $3; exit }')" || true
    if [[ -n "${existing_key}" && "${existing_key}" != "${scanned_key}" ]]; then
      if [[ "${CONFIRM_ANSIBLE_HOST_KEY_CHANGE:-}" != "yes" ]]; then
        [[ -t 0 ]] || die "SSH host key changed for ${node} (${ip}); verify the VM and rerun with CONFIRM_ANSIBLE_HOST_KEY_CHANGE=yes."
        printf 'SSH host key changed for %s (%s). Trust the new key? [y/N] ' "${node}" "${ip}" >&2
        read -r answer
        [[ "${answer}" == "y" || "${answer}" == "Y" ]] || die "Host-key update cancelled."
      fi
      ssh-keygen -q -R "${ip}" -f "${KNOWN_HOSTS}"
      existing_key=""
    fi
    if [[ -z "${existing_key}" ]]; then
      info "Recording the SSH host key for ${node} (${ip}) using local TOFU"
      cat "${scan_file}" >>"${KNOWN_HOSTS}"
    fi
  done
  rm -f "${scan_file}"
  scan_file=""
}

verify_hosts() {
  local node ip
  for node in "${NODES[@]}"; do
    ip="$(node_ip "${node}")"
    ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes \
      -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=${KNOWN_HOSTS}" \
      -i "${PRIVATE_KEY}" "ubuntu@${ip}" true ||
      die "Dedicated SSH verification failed for ${node} (${ip})."
  done
  info "Dedicated SSH and host-key verification passed on all managed nodes."
}

action="${1:-all}"
prepare_key
case "${action}" in
prepare) ;;
migrate) migrate_existing_nodes ;;
trust) trust_hosts ;;
verify) verify_hosts ;;
all)
  migrate_existing_nodes
  trust_hosts
  verify_hosts
  ;;
*) die "Usage: $0 {prepare|migrate|trust|verify|all}" ;;
esac
