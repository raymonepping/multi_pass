output "namespaces" {
  value = sort([for namespace in vault_namespace.this : namespace.path_fq])
}

output "mounts" {
  value = {
    for key, mount in vault_mount.this : key => "${mount.namespace}/${mount.path}"
  }
}
