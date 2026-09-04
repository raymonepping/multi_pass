terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.11.0"
    }
  }
}

# The non-secret address comes from deployment state. VAULT_TOKEN and
# VAULT_CACERT remain process-environment inputs supplied by scripts/platform.sh.
provider "vault" {
  address = data.terraform_remote_state.deployment.outputs.vault_api_addresses["vault-1"]
}
