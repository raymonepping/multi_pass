output "namespaces" {
  value = sort([for namespace in vault_namespace.this : namespace.path_fq])
}

output "mounts" {
  value = {
    for key, mount in vault_mount.this : key => "${mount.namespace}/${mount.path}"
  }
}

output "vault_address" {
  description = "Non-secret Vault API address read from deployment state."
  value       = data.terraform_remote_state.deployment.outputs.vault_api_addresses["vault-1"]
}
