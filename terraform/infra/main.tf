locals {
  node_names = [for index in range(var.node_count) : "vault-${index + 1}"]
  nodes      = toset(local.node_names)

  ansible_public_key_path = coalesce(
    var.ansible_public_key_path,
    abspath("${path.module}/../../.secrets/ansible/id_ed25519.pub"),
  )
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
