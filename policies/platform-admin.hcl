# Lab-only administrative policy used by the Vault Terraform provider.
# The token is generated externally and never placed in Terraform configuration.
path "sys/namespaces/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "auth/token/create" {
  capabilities = ["create", "update", "sudo"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
