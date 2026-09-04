data "terraform_remote_state" "deployment" {
  backend = "local"

  config = {
    path = abspath("${path.module}/../infra/terraform.tfstate")
  }
}

resource "vault_namespace" "this" {
  for_each = var.namespaces
  path     = each.value
}

resource "vault_mount" "this" {
  for_each = var.mounts

  namespace   = vault_namespace.this[each.value.namespace].path_fq
  path        = each.value.path
  type        = each.value.type
  description = each.value.description
  options     = each.value.options
}
