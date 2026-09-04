locals {
  nodes = toset([for index in range(var.node_count) : "vault-${index + 1}"])
}

resource "multipass_instance" "vault" {
  for_each = local.nodes

  name            = each.key
  image           = "file://${var.image_path}"
  cpus            = var.cpus
  memory          = var.memory
  disk            = var.disk
  cloud_init_file = "${path.module}/cloud-init/rhel.yaml"
}
