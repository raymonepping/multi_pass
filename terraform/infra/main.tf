locals {
  node_names = [for index in range(var.node_count) : "vault-${index + 1}"]
  nodes      = toset(local.node_names)

  ansible_public_key_path = coalesce(
    var.ansible_public_key_path,
    abspath("${path.module}/../../.secrets/ansible/id_ed25519.pub"),
  )
  ansible_private_key_path = trimsuffix(local.ansible_public_key_path, ".pub")
  ansible_known_hosts_path = abspath("${path.module}/../../.secrets/ansible/known_hosts")
}

resource "local_file" "cloud_init" {
  filename             = abspath("${path.module}/../../.build/cloud-init/rhel.yaml")
  directory_permission = "0700"
  file_permission      = "0600"
  content = templatefile("${path.module}/cloud-init/rhel.yaml.tftpl", {
    ansible_public_key = trimspace(file(local.ansible_public_key_path))
  })
}

resource "multipass_instance" "vault" {
  for_each = local.nodes

  name            = each.key
  image           = "file://${var.image_path}"
  cpus            = var.cpus
  memory          = var.memory
  disk            = var.disk
  cloud_init_file = local_file.cloud_init.filename

  # Existing lab VMs predate the generated cloud-init file. Cloud-init is
  # immutable after creation, so changing its source must never replace them.
  # Newly created instances still receive the generated dedicated public key.
  lifecycle {
    ignore_changes = [cloud_init_file]
  }
}

resource "ansible_group" "vault" {
  name = "vault"

  variables = {
    ansible_user                 = "ubuntu"
    ansible_become               = true
    ansible_become_method        = "sudo"
    ansible_python_interpreter   = "/usr/bin/python3.9"
    ansible_ssh_private_key_file = local.ansible_private_key_path
    ansible_ssh_common_args      = "-F /dev/null -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${local.ansible_known_hosts_path}"
  }
}

resource "ansible_host" "vault" {
  for_each = multipass_instance.vault

  name   = each.key
  groups = [ansible_group.vault.name]

  variables = {
    ansible_host = each.value.ipv4[0]
    vault_role   = each.key == local.node_names[0] ? "leader" : "follower"
  }
}
