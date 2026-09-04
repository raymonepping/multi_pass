output "node_names" {
  description = "Terraform-managed Vault VM names."
  value       = sort([for node in multipass_instance.vault : node.name])
}

output "node_ipv4" {
  description = "Primary IPv4 address for each Vault VM."
  value = {
    for name, node in multipass_instance.vault : name => node.ipv4[0]
  }
}
