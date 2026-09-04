#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd terraform
require_cmd multipass
require_managed_nodes
prepare_local_dirs

RHEL_DNS_SERVERS="${RHEL_DNS_SERVERS:-1.1.1.1,1.0.0.1}"
[[ "${RHEL_DNS_SERVERS}" =~ ^[0-9a-fA-F:.,[:space:]]+$ ]] ||
  die "RHEL_DNS_SERVERS must contain only IP addresses separated by commas or spaces."

credentials_file=""
cleanup() {
  if [[ -n "${credentials_file}" && -f "${credentials_file}" ]]; then
    rm -f "${credentials_file}"
  fi
}
trap cleanup EXIT HUP INT TERM

make_credentials_file() {
  [[ -n "${RHSM_ORG:-}" && -n "${RHSM_ACTIVATION_KEY:-}" ]] ||
    die "RHEL registration is required. Export RHSM_ORG and RHSM_ACTIVATION_KEY, then rerun 'make rhel-prepare'."
  [[ "${RHSM_ORG}" =~ ^[A-Za-z0-9._:-]+$ ]] || die "RHSM_ORG contains unsupported characters."
  [[ "${RHSM_ACTIVATION_KEY}" =~ ^[A-Za-z0-9._:-]+$ ]] || die "RHSM_ACTIVATION_KEY contains unsupported characters."

  if [[ -z "${credentials_file}" ]]; then
    credentials_file="$(mktemp "${SECRETS_DIR}/rhsm-credentials.XXXXXX")"
    chmod 600 "${credentials_file}"
    printf '%s\n%s\n' "${RHSM_ORG}" "${RHSM_ACTIVATION_KEY}" >"${credentials_file}"
  fi
}

for node in "${NODES[@]}"; do
  info "Preparing RHEL prerequisites on ${node}"
  [[ "$(multipass exec "${node}" -- uname -m)" == "aarch64" ]] || die "${node} is not ARM64."
  multipass exec "${node}" -- grep -q '^PLATFORM_ID="platform:el9"' /etc/os-release || die "${node} is not RHEL 9."

  dns_works="$(multipass exec "${node}" -- sh -c \
    'if getent ahosts subscription.rhsm.redhat.com >/dev/null 2>&1; then printf yes; else printf no; fi')"
  if [[ "${dns_works}" == "no" ]]; then
    raw_network_works="$(multipass exec "${node}" -- sh -c \
      'if curl -kfsS --connect-timeout 5 --max-time 10 https://1.1.1.1/ >/dev/null 2>&1; then printf yes; else printf no; fi')"
    [[ "${raw_network_works}" == "yes" ]] ||
      die "${node} has neither working DNS nor raw HTTPS connectivity; repair Multipass networking first."
    connection_name="$(multipass exec "${node}" -- nmcli -g GENERAL.CONNECTION device show eth0)"
    [[ -n "${connection_name}" && "${connection_name}" != "--" ]] || die "Cannot identify ${node}'s NetworkManager connection."
    info "Repairing DNS on ${node} through NetworkManager using ${RHEL_DNS_SERVERS}"
    multipass exec "${node}" -- sudo nmcli connection modify "${connection_name}" \
      ipv4.ignore-auto-dns yes ipv4.dns "${RHEL_DNS_SERVERS}"
    # NetworkManager can briefly disrupt Multipass's SSH channel while applying
    # DNS. Queue the reapply independently, then poll through fresh connections.
    multipass exec "${node}" -- sudo systemd-run --collect /usr/bin/nmcli device reapply eth0 >/dev/null
    dns_works="no"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      dns_works="$(multipass exec "${node}" -- sh -c \
        'if getent ahosts subscription.rhsm.redhat.com >/dev/null 2>&1; then printf yes; else printf no; fi')"
      [[ "${dns_works}" == "yes" ]] && break
      sleep 1
    done
    [[ "${dns_works}" == "yes" ]] || die "DNS repair did not restore Red Hat endpoint resolution on ${node}."
  fi

  firewalld_installed="$(multipass exec "${node}" -- sh -c \
    'if rpm -q firewalld >/dev/null 2>&1; then printf yes; else printf no; fi')"
  if [[ "${firewalld_installed}" == "no" ]]; then
    rhsm_registered="$(multipass exec "${node}" -- sh -c \
      'if sudo subscription-manager identity >/dev/null 2>&1; then printf yes; else printf no; fi')"
    if [[ "${rhsm_registered}" == "no" ]]; then
      make_credentials_file
      guest_credentials="/tmp/.rhsm-credentials"
      guest_helper="/tmp/rhsm-register-guest.sh"
      info "Registering ${node} with Red Hat using the supplied activation key (values suppressed)"
      multipass transfer "${credentials_file}" "${node}:${guest_credentials}"
      multipass transfer "${SCRIPT_DIR}/rhsm-register-guest.sh" "${node}:${guest_helper}"
      multipass exec "${node}" -- chmod 600 "${guest_credentials}" "${guest_helper}"
      if ! multipass exec "${node}" -- sudo /bin/bash "${guest_helper}" "${guest_credentials}"; then
        multipass exec "${node}" -- rm -f "${guest_credentials}" "${guest_helper}" || true
        die "Red Hat registration failed on ${node}."
      fi
      multipass exec "${node}" -- rm -f "${guest_helper}"
    else
      info "${node} is already registered with Red Hat."
    fi

    repo_available="$(multipass exec "${node}" -- sudo sh -c \
      "if dnf repolist --enabled -q | awk 'NR > 1 { found=1 } END { exit !found }'; then printf yes; else printf no; fi")"
    [[ "${repo_available}" == "yes" ]] || die "No enabled RHEL repository is available on ${node} after registration."
    package_available="$(multipass exec "${node}" -- sudo sh -c \
      'if dnf --quiet list --available firewalld >/dev/null 2>&1; then printf yes; else printf no; fi')"
    [[ "${package_available}" == "yes" ]] || die "Enabled repositories on ${node} do not provide firewalld."
    info "Installing firewalld from enabled RHEL repositories on ${node}"
    multipass exec "${node}" -- sudo dnf install -y firewalld
  else
    info "firewalld is already installed on ${node}; registration is not changed."
  fi

  multipass exec "${node}" -- sudo systemctl enable --now firewalld
  firewalld_active="$(multipass exec "${node}" -- sh -c \
    'if sudo systemctl is-active --quiet firewalld; then printf yes; else printf no; fi')"
  [[ "${firewalld_active}" == "yes" ]] || die "firewalld is not active on ${node}."
done

info "RHEL prerequisite preparation passed on all three Terraform-managed nodes."
