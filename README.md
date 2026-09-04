# Reproducible Vault Enterprise lab on Multipass

This project creates a three-node Vault Enterprise cluster on local RHEL 9
ARM64 Multipass VMs. The complete workflow is:

```text
Terraform deployment
  -> Terraform Ansible provider
  -> Ansible RHEL/Vault convergence and bootstrap
  -> Vault Terraform provider
  -> validation
```

The normal operator interface is one command:

```bash
make lab
```

It is deliberately implemented as three stateful phases rather than one giant
Terraform apply. The Vault provider needs a token which Ansible creates during
bootstrap, so the platform apply starts only after Ansible has proved the
cluster healthy.

## Ownership boundaries

| Phase | Directory | Owns |
|---|---|---|
| Deployment | `terraform/infra` | Three Multipass VMs and non-secret topology outputs |
| Convergence | `terraform/ansible`, `ansible` | Terraform-triggered Ansible run, RHEL, Vault, TLS, bootstrap and validation |
| Platform | `terraform/platform` | Vault namespaces and secret-engine mounts |

`terraform/ansible` reads `ansible_nodes` from deployment state and passes the
JSON node model to `ansible_playbook`. `ansible/terraform.yml` creates the
inventory in memory before importing the convergence playbook. This works on
the first run and avoids depending on an inventory plugin reading state before
new resources have been persisted.

The `cloud.terraform.terraform_provider` inventory plugin was tested but is not
used: version 4.0.0 is incompatible with the installed Ansible Core 2.21, and
the state-backed approach also has a documented first-apply timing limitation.

## Prerequisites

- Apple Silicon Mac with Multipass
- Terraform `>= 1.11, < 2.0`
- Ansible Core `>= 2.15`
- Vault CLI, `jq`, `openssl`, `curl`, `unzip`, `shasum`, `ssh-keygen`,
  `ssh-keyscan`, and `rg`
- RHEL 9.8 ARM64 qcow2, default
  `/Users/Shared/rhel-9.8-aarch64-kvm.qcow2`
- a raw Vault Enterprise license at `.secrets/keys/vault.hclic`, or an absolute
  path in `VAULT_LICENSE_FILE`
- `RHSM_ORG` and `RHSM_ACTIVATION_KEY` only when a new RHEL guest needs package
  registration

Copy `.env.example` to an ignored file if useful, then export the required
values into the current shell. The automation never sources an environment
file automatically.

## First run or full reconciliation

```bash
make lab
```

The command:

1. validates local prerequisites;
2. installs pinned Ansible collections into the ignored `.cache` directory;
3. creates a dedicated SSH identity under `.secrets/ansible`;
4. applies deployment Terraform;
5. authorizes the dedicated public key on existing managed nodes when
   explicitly confirmed and records their SSH host keys using local TOFU;
6. applies `terraform/ansible`, which waits for Ansible and propagates failure;
7. validates the Vault cluster;
8. applies `terraform/platform` using the ignored platform token;
9. requires clean orchestration and platform plans; and
10. checks known secret values are absent from every Terraform state file.

On the one-time migration of existing VMs, approve the dedicated public key at
the prompt. For non-interactive execution use:

```bash
CONFIRM_ANSIBLE_SSH_MIGRATION=yes make lab
```

The migration only appends the generated public key to the `ubuntu` account on
`vault-1`, `vault-2`, and `vault-3`. It never replaces a VM. Cleanly created VMs
receive the same public key through rendered cloud-init.

## Useful targets

| Target | Purpose |
|---|---|
| `make check` | Static prerequisites and formatting |
| `make deployment-plan` | Preview VM deployment changes |
| `make deployment` | Apply VM deployment only |
| `make ansible-ssh` | Authorize/verify the dedicated key and host trust |
| `make ansible-check` | Syntax and read-only Terraform-to-Ansible ping proof |
| `make ansible-plan` | Preview the orchestration resource |
| `make ansible-converge` | Force a fresh provider-launched idempotent convergence |
| `make ansible-validate` | Require a clean orchestration plan |
| `make validate` | Read-only live Vault cluster validation |
| `make platform-plan` | Preview Vault platform resources |
| `make platform` | Apply Vault platform resources |
| `make platform-validate` | Require an empty platform plan |
| `make state-secret-check` | Verify known secrets are absent from Terraform state |
| `make rhel-unregister` | Separately confirmed RHSM unregistration |
| `make destroy` | Interactively destroy only Terraform-managed VMs |

The original shell phase targets remain available as a recovery/reference
path: `rhel-prepare`, `tls`, `install`, `license`, `configure`, and `bootstrap`.

## Secret boundary

Terraform receives node names, IP addresses, roles, API addresses, and paths to
ignored files. It never receives license contents, RHSM activation-key values,
SSH/TLS private keys, root/platform tokens, or Shamir keys.

Sensitive files stay under `.secrets` with restrictive permissions:

```text
.secrets/
├── ansible/id_ed25519
├── ansible/known_hosts
├── keys/vault.hclic
├── tls/ca.key
├── tls/vault-{1,2,3}.key
├── vault-init.json
└── platform-token
```

The Ansible provider retains playbook stdout and stderr in its ignored state.
Every task that handles credentials uses `no_log: true`, and
`make state-secret-check` compares known values without printing them.

## Documentation

- [Ansible workflow](docs/ansible-getting-started.md)
- [Terraform roots](docs/terraform-getting-started.md)
- [Operations and recovery](docs/operations.md)
- [Shell fallback](docs/shell-getting-started.md)
- [Vault usage](docs/vault-getting-started.md)
- [Release checklist](docs/release-checklist.md)

## License

[GPLv3](LICENSE)
