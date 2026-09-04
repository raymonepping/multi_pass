terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    ansible = {
      source  = "ansible/ansible"
      version = "1.5.0"
    }
  }
}
