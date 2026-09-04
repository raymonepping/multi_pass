#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd openssl
require_cmd terraform
require_managed_nodes
prepare_local_dirs
mkdir -p "${TLS_DIR}"
chmod 700 "${TLS_DIR}"

if [[ ! -f "${TLS_DIR}/ca.key" || ! -f "${TLS_DIR}/ca.crt" ]]; then
  info "Generating local Vault lab CA"
  openssl genrsa -out "${TLS_DIR}/ca.key" 4096
  openssl req -x509 -new -sha256 -days 3650 \
    -key "${TLS_DIR}/ca.key" \
    -subj "/CN=Vault Multipass Lab CA" \
    -out "${TLS_DIR}/ca.crt"
  chmod 600 "${TLS_DIR}/ca.key" "${TLS_DIR}/ca.crt"
fi

for node in "${NODES[@]}"; do
  ip="$(node_ip "${node}")"
  cert="${TLS_DIR}/${node}.crt"
  regenerate=true
  if [[ -f "${cert}" ]] && openssl x509 -checkend 86400 -noout -in "${cert}" >/dev/null 2>&1; then
    if openssl x509 -in "${cert}" -noout -ext subjectAltName | rg -q "IP Address:${ip}"; then
      regenerate=false
    fi
  fi

  if [[ "${regenerate}" == true ]]; then
    info "Generating certificate for ${node} (${ip})"
    ext_file="$(mktemp "${TMPDIR:-/tmp}/vault-san.XXXXXX")"
    trap 'rm -f "${ext_file}"' EXIT
    printf '%s\n' \
      '[req]' \
      'distinguished_name = dn' \
      'prompt = no' \
      'req_extensions = req_ext' \
      '[dn]' \
      "CN = ${node}" \
      '[req_ext]' \
      'subjectAltName = @alt_names' \
      '[alt_names]' \
      "DNS.1 = ${node}" \
      'DNS.2 = localhost' \
      "IP.1 = ${ip}" \
      'IP.2 = 127.0.0.1' >"${ext_file}"
    openssl genrsa -out "${TLS_DIR}/${node}.key" 3072
    openssl req -new -key "${TLS_DIR}/${node}.key" -config "${ext_file}" -out "${TLS_DIR}/${node}.csr"
    openssl x509 -req -sha256 -days 825 \
      -in "${TLS_DIR}/${node}.csr" \
      -CA "${TLS_DIR}/ca.crt" -CAkey "${TLS_DIR}/ca.key" -CAcreateserial \
      -extfile "${ext_file}" -extensions req_ext \
      -out "${cert}"
    rm -f "${ext_file}" "${TLS_DIR}/${node}.csr"
    trap - EXIT
    chmod 600 "${TLS_DIR}/${node}.key" "${cert}"
  else
    info "Existing certificate for ${node} is valid and matches its current IP."
  fi
done

info "TLS material is ready under ${TLS_DIR} (ignored by Git)."
