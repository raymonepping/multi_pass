# multi_pass

> **New to Vault?** See [docs/vault-getting-started.md](docs/vault-getting-started.md) for a hands-on walkthrough: shell setup, reading and writing secrets, Transit encryption, PKI, policies, and more.

A fully automated lab for running a three-node HashiCorp Vault Enterprise cluster on local RHEL 9 VMs using [Multipass](https://multipass.run). Infrastructure is provisioned with Terraform, the OS and Vault bootstrap layer is driven by shell scripts, and ongoing Vault configuration is managed as code through the Vault Terraform provider.

## Architecture

```
Terraform (infra)     →  three RHEL 9 Multipass VMs
Shell scripts         →  TLS, Vault binary, license, config, init, unseal
Terraform (platform)  →  namespaces, secret engine mounts, auth, policies
```

## Prerequisites

| Tool | Purpose |
|---|---|
| `terraform` >= 1.11 | Infrastructure and Vault configuration |
| `multipass` | Local VM management |
| `vault` (CLI) | Bootstrap and validation |
| `jq`, `openssl`, `curl`, `unzip`, `shasum` | Script dependencies |

A RHEL 9 ARM64 qcow2 image is required at `/Users/Shared/rhel-9.8-aarch64-kvm.qcow2` (override with `TF_VAR_image_path`).

Place your licenses at:

```
.secrets/keys/vault.hclic
.secrets/keys/terraform.hclic
```

## Full runbook

```bash
make check             # verify tools, image, and licenses
make infra             # create vault-1, vault-2, vault-3 VMs
make tls               # generate CA + per-node certs, push to guests
make install           # install Vault Enterprise binary on all nodes
make license           # push vault.hclic to all nodes
make configure         # write vault.hcl, enable and start the service
make bootstrap         # operator init, Raft join, unseal, platform token
make validate          # cluster health check (1 active, 2 standby, 3 voters)
make platform          # apply Terraform platform layer (namespaces, mounts)
make platform-validate # confirm Terraform plan is clean (no drift)
```

Each target is idempotent and can be rerun after fixing a reported error.

## Make targets

| Target | Description |
|---|---|
| `check` | Prerequisite and license validation |
| `infra-plan` | Terraform plan for VM infrastructure |
| `infra` | Create or update VMs |
| `rhel-prepare` | Register RHEL nodes with RHSM and install `firewalld` |
| `rhel-unregister` | Unregister nodes from RHSM before destroy |
| `infra-validate` | Verify Terraform state and VM reachability |
| `tls` | Generate and distribute TLS material |
| `install` | Install Vault Enterprise binary |
| `license` | Push Vault license to all nodes |
| `configure` | Write Vault config and start the service |
| `bootstrap` | Initialize, join Raft, unseal, create platform token |
| `validate` | Live cluster health check |
| `platform-plan` | Terraform plan for Vault configuration |
| `platform` | Apply Vault configuration |
| `platform-validate` | Drift detection for Vault configuration |
| `failover-help` | Print the manual failover acceptance test |
| `destroy` | Destroy VMs (Terraform interactive confirm) |

## Secrets layout

```
.secrets/              # mode 700, never committed
├── keys/
│   ├── vault.hclic    # Vault Enterprise license
│   └── terraform.hclic
├── tls/               # CA and per-node certs
├── vault-init.json    # root token + unseal keys — back this up
└── platform-token     # scoped Terraform token
```

## Override reference

| Variable | Default | Purpose |
|---|---|---|
| `TF_VAR_image_path` | `/Users/Shared/rhel-9.8-aarch64-kvm.qcow2` | RHEL qcow2 image |
| `VAULT_LICENSE_FILE` | `.secrets/keys/vault.hclic` | Vault license path |
| `TF_LICENSE_PATH` | `.secrets/keys/terraform.hclic` | Terraform license path |
| `VAULT_VERSION` | `2.1.0+ent` | Vault Enterprise version to install |
| `RHSM_ORG` + `RHSM_ACTIVATION_KEY` | — | Required only for `make rhel-prepare` |

## License

[GPLv3](LICENSE)
