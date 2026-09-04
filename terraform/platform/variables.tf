variable "namespaces" {
  description = "Flat Enterprise namespaces created below the root namespace."
  type        = set(string)
  default     = ["engineering", "operations"]

  validation {
    condition     = alltrue([for name in var.namespaces : can(regex("^[a-z][a-z0-9-]*$", name))])
    error_message = "Namespace names must be lowercase path segments without slashes."
  }
}

variable "mounts" {
  description = "Non-secret Vault mount definitions keyed by a stable logical name."
  type = map(object({
    namespace   = string
    path        = string
    type        = string
    description = optional(string, "Managed by Terraform")
    options     = optional(map(string), {})
  }))

  default = {
    engineering_kv = {
      namespace = "engineering"
      path      = "kv"
      type      = "kv"
      options   = { version = "2" }
    }
    engineering_transit = {
      namespace = "engineering"
      path      = "transit"
      type      = "transit"
    }
    operations_pki = {
      namespace = "operations"
      path      = "pki"
      type      = "pki"
    }
  }

  validation {
    condition = alltrue([
      for mount in values(var.mounts) :
      contains(var.namespaces, mount.namespace) && contains(["kv", "transit", "pki"], mount.type)
    ])
    error_message = "Each mount must reference a declared namespace and use kv, transit, or pki."
  }
}
