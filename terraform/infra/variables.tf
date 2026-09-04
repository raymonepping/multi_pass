variable "image_path" {
  description = "Absolute path to the RHEL 9.8 ARM64 qcow2 image."
  type        = string
  default     = "/Users/Shared/rhel-9.8-aarch64-kvm.qcow2"

  validation {
    condition     = startswith(var.image_path, "/")
    error_message = "image_path must be an absolute path."
  }
}

variable "node_count" {
  description = "Number of Vault nodes. This lab intentionally requires three."
  type        = number
  default     = 3

  validation {
    condition     = var.node_count == 3
    error_message = "This lab is designed and validated for exactly three nodes."
  }
}

variable "cpus" {
  type    = number
  default = 2
}

variable "memory" {
  type    = string
  default = "4G"
}

variable "disk" {
  type    = string
  default = "20G"
}

variable "command_timeout_seconds" {
  type    = number
  default = 900
}
