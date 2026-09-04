terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    multipass = {
      source  = "todoroff/multipass"
      version = "1.7.1"
    }
  }
}

provider "multipass" {
  command_timeout = var.command_timeout_seconds
}
