ui               = true
disable_mlock    = true
api_addr         = "https://@IP@:8200"
cluster_addr     = "https://@IP@:8201"
license_path     = "/opt/vault/vault.hclic"

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "@NODE@"
}

listener "tcp" {
  address            = "0.0.0.0:8200"
  cluster_address    = "0.0.0.0:8201"
  tls_cert_file      = "/opt/vault/tls/server.crt"
  tls_key_file       = "/opt/vault/tls/server.key"
  tls_client_ca_file = "/opt/vault/tls/ca.crt"
  tls_min_version    = "tls12"
}

telemetry {
  disable_hostname = true
}
