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

output "ansible_nodes" {
  description = "Non-secret node topology consumed by the Ansible orchestration root."
  value = {
    for name, node in multipass_instance.vault : name => {
      ansible_host = node.ipv4[0]
      vault_role   = name == local.node_names[0] ? "leader" : "follower"
    }
  }
}

output "vault_api_addresses" {
  description = "TLS Vault API address for each node."
  value = {
    for name, node in multipass_instance.vault : name => "https://${node.ipv4[0]}:8200"
  }
}
