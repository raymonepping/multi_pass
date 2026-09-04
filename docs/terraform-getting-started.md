# Terraform — Getting Started

This guide covers both Terraform layers in the project: the infrastructure
layer that creates the VMs, and the platform layer that configures Vault.
It assumes you have completed `make check` and have your licenses in place.

---

## The two layers

| Layer | Directory | Provider | What it owns |
|---|---|---|---|
| `infra` | `terraform/infra/` | `todoroff/multipass` | vault-1, vault-2, vault-3 VMs |
| `platform` | `terraform/platform/` | `hashicorp/vault` | Namespaces, mounts, auth, policies |

They are separate state files and run independently. `infra` must exist before
`platform` can run — the platform layer needs a live Vault cluster to connect to.

---

## Layer 1 — Infrastructure (`terraform/infra/`)

### First run

```bash
make check       # verify tools, image path, and licenses
make infra-plan  # review what Terraform will create (no changes made)
make infra       # create the three VMs
```

### What gets created

Three Multipass instances named `vault-1`, `vault-2`, `vault-3`, each
provisioned from the RHEL 9 qcow2 image with cloud-init applied.

### Variables

All variables have defaults. Override on the command line or via environment:

| Variable | Default | How to override |
|---|---|---|
| `image_path` | `/Users/Shared/rhel-9.8-aarch64-kvm.qcow2` | `export TF_VAR_image_path=/your/path.qcow2` |
| `cpus` | `2` | `export TF_VAR_cpus=4` |
| `memory` | `4G` | `export TF_VAR_memory=8G` |
| `disk` | `20G` | `export TF_VAR_disk=40G` |
| `node_count` | `3` | Fixed at 3 — the lab requires exactly three nodes |

### Useful commands

```bash
# Review the plan without applying
terraform -chdir=terraform/infra plan

# Check outputs (node IPs)
terraform -chdir=terraform/infra output

# Get a specific IP
terraform -chdir=terraform/infra output -json node_ipv4 | jq -r '.["vault-1"]'

# Validate HCL syntax
terraform -chdir=terraform/infra validate

# Check formatting (make check runs this automatically)
terraform -chdir=terraform/infra fmt -check -recursive
```

### Teardown

```bash
make destroy    # interactive confirmation — destroys only the three vault VMs
```

If nodes were RHSM-registered, unregister first:

```bash
CONFIRM_RHSM_UNREGISTER=yes make rhel-unregister
make destroy
```

---

## Layer 2 — Platform (`terraform/platform/`)

### Prerequisites

The cluster must be bootstrapped and `make validate` must pass before running
the platform layer. The platform token at `.secrets/platform-token` is what
authenticates Terraform to Vault.

### First run

```bash
make platform-plan  # review what will be created
make platform       # apply namespaces and mounts
make platform-validate  # confirm plan is clean (no drift)
```

### What gets created (defaults)

```
engineering/          ← vault_namespace
  └── kv/   (kv v2)  ← vault_mount
  └── transit/        ← vault_mount
operations/           ← vault_namespace
  └── pki/            ← vault_mount
```

### Adding a new namespace

Edit [`terraform/platform/variables.tf`](../terraform/platform/variables.tf) —
add the name to the `namespaces` default set:

```hcl
variable "namespaces" {
  default = ["engineering", "operations", "security"]
  ...
}
```

Then run `make platform-plan` to review, `make platform` to apply.

### Adding a new secret engine mount

Add an entry to the `mounts` variable in
[`variables.tf`](../terraform/platform/variables.tf):

```hcl
security_kv = {
  namespace = "security"
  path      = "kv"
  type      = "kv"
  options   = { version = "2" }
}
```

Supported types: `kv`, `transit`, `pki`. The validation block enforces this —
add new types there if you need others.

### Adding new resource types

Create a new `.tf` file in `terraform/platform/`. The provider, credentials,
and CA cert are already wired in `versions.tf` via environment variables set
by `scripts/platform.sh`. Example — adding a policy:

```hcl
# terraform/platform/policies.tf
resource "vault_policy" "example" {
  namespace = vault_namespace.this["engineering"].path_fq
  name      = "example-readonly"
  policy    = file("${path.module}/../../policies/example-readonly.hcl")
}
```

### Drift detection

```bash
make platform-validate
```

Runs `terraform plan -detailed-exitcode`. Exit code 0 = no changes. Exit
code 2 = drift detected (resources exist in Vault that differ from state).

### Useful commands

```bash
# Show current state
terraform -chdir=terraform/platform show

# List resources in state
terraform -chdir=terraform/platform state list

# Show a specific resource
terraform -chdir=terraform/platform state show 'vault_namespace.this["engineering"]'

# Import a manually created resource into state
terraform -chdir=terraform/platform import \
  'vault_namespace.this["security"]' security/

# Remove a resource from state without destroying it
terraform -chdir=terraform/platform state rm 'vault_mount.this["engineering_kv"]'

# Full plan with explicit var file
terraform -chdir=terraform/platform plan \
  -var-file=terraform/platform/terraform.tfvars.example
```

### After destroy / reprovisioning

The platform state references Vault resources that no longer exist after
`make destroy`. Reset before reprovisioning:

```bash
rm -f terraform/platform/terraform.tfstate \
      terraform/platform/terraform.tfstate.backup
```

---

## Environment variables used by both layers

| Variable | Used by | Purpose |
|---|---|---|
| `TF_VAR_image_path` | `infra` | RHEL qcow2 image path |
| `TF_LICENSE_PATH` | both | Terraform Enterprise license (set by `common.sh`) |
| `VAULT_ADDR` | `platform` | Active Vault node address (set by `platform.sh`) |
| `VAULT_CACERT` | `platform` | CA certificate path (set by `platform.sh`) |
| `VAULT_TOKEN` | `platform` | Platform token from `.secrets/platform-token` |
