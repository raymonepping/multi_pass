output "deployment_nodes" {
  description = "Non-secret nodes converged by the Ansible provider."
  value       = sort(keys(data.terraform_remote_state.deployment.outputs.ansible_nodes))
}

output "automation_digest" {
  description = "Digest that causes changed automation content to be reapplied."
  value       = local.automation_digest
}
