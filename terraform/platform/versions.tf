terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.11.0"
    }
  }
}

# VAULT_ADDR, VAULT_TOKEN, and VAULT_CACERT are supplied by scripts/platform.sh.
provider "vault" {}
