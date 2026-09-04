data "terraform_remote_state" "deployment" {
  backend = "local"

  config = {
    path = abspath("${path.module}/../infra/terraform.tfstate")
  }
}

locals {
  repository_root = abspath("${path.module}/../..")
  automation_files = sort(concat(
    [for filename in fileset("${local.repository_root}/ansible", "**/*.yml") : "ansible/${filename}"],
    [for filename in fileset("${local.repository_root}/ansible", "**/*.j2") : "ansible/${filename}"],
    [for filename in fileset("${local.repository_root}/templates", "**/*") : "templates/${filename}"],
    ["policies/platform-admin.hcl"],
  ))
  automation_digest = sha256(join("", [
    for filename in local.automation_files : filesha256("${local.repository_root}/${filename}")
  ]))
}

resource "ansible_playbook" "vault_lab" {
  name       = "localhost"
  groups     = ["terraform_orchestrator"]
  playbook   = "${local.repository_root}/ansible/terraform.yml"
  replayable = false

  extra_vars = {
    vault_nodes_json         = jsonencode(data.terraform_remote_state.deployment.outputs.ansible_nodes)
    ansible_private_key_file = "${local.repository_root}/.secrets/ansible/id_ed25519"
    ansible_known_hosts_file = "${local.repository_root}/.secrets/ansible/known_hosts"
    automation_digest        = local.automation_digest
  }

  timeouts {
    create = "45m"
  }
}
