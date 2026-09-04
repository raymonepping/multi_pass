# multi_pass

## Documentation

| Guide | What it covers |
|---|---|
| [Vault — Getting Started](docs/vault-getting-started.md) | Shell setup, KV v2, Transit, PKI, policies, tokens, unseal |
| [Shell Scripts — Getting Started](docs/shell-getting-started.md) | Each script explained, Make targets, overrides, resume after failure |
| [Ansible — Getting Started](docs/ansible-getting-started.md) | Playbook usage, tags, dry-run, role reference, extending |
| [Terraform — Getting Started](docs/terraform-getting-started.md) | Infra layer, platform layer, variables, drift detection, state commands |
| [Operations](docs/operations.md) | Resume points, failover test, day-2 changes, teardown |
| [Release Checklist](docs/release-checklist.md) | Pre-tag gates, tagging, post-release steps |

A fully automated lab for running a three-node HashiCorp Vault Enterprise cluster on local RHEL 9 VMs using [Multipass](https://multipass.run). Infrastructure is provisioned with Terraform, the OS and Vault bootstrap layer is driven by shell scripts or Ansible, and ongoing Vault configuration is managed as code through the Vault Terraform provider.

## Architecture

```
Terraform (infra)     →  three RHEL 9 Multipass VMs
Shell scripts/Ansible →  TLS, Vault binary, license, config, init, unseal
Terraform (platform)  →  namespaces, secret engine mounts, auth, policies
```

The project is structured as three distinct phases with clear handoff points between them:

| Phase | Tool | Owns |
|---|---|---|
| 1 — Infrastructure | Terraform (`terraform/infra/`) | VMs exist and are reachable |
| 2 — OS & bootstrap | Shell scripts **or** Ansible (`ansible/`) | Binary, TLS, config, init, unseal |
| 3 — Vault config | Terraform (`terraform/platform/`) | Everything inside Vault |

### Lab vs production: shell scripts or Ansible

Phase 2 ships with **two implementations** — use whichever fits your workflow:

| | Shell scripts (`scripts/`) | Ansible (`ansible/`) |
|---|---|---|
| Entry point | `make tls install license configure bootstrap` | `ansible-playbook ansible/site.yml` |
| Transport | `multipass exec` / `multipass transfer` | Direct SSH |
| Best for | Learning, stepping through individual stages | Repeated rebuilds, team use, moving to real hosts |
| Idempotent | Yes | Yes |

The Terraform phases (1 and 3) are identical regardless of which Phase 2 path you use.

| Script | Ansible role equivalent |
|---|---|
| `tls.sh` | `roles/tls` |
| `install.sh` | `roles/vault_install` |
| `license.sh` | `roles/vault_license` |
| `configure.sh` | `roles/vault_configure` |
| `bootstrap.sh` | `roles/vault_bootstrap` |

---

## Prerequisites

| Tool | Purpose |
|---|---|
| `terraform` >= 1.11 | Infrastructure and Vault configuration |
| `multipass` | Local VM management |
| `vault` (CLI) | Bootstrap and validation |
| `jq`, `openssl`, `curl`, `unzip`, `shasum` | Shell script dependencies |
| `ansible` >= 2.15 | Ansible path only — `brew install ansible` |
| `python3` | Required by the dynamic inventory script |

A RHEL 9 ARM64 qcow2 image is required at `/Users/Shared/rhel-9.8-aarch64-kvm.qcow2` (override with `TF_VAR_image_path`).

Place your licenses at:

```
.secrets/keys/vault.hclic
.secrets/keys/terraform.hclic
```

---

## Full runbook — shell scripts path

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

## Full runbook — Ansible path

```bash
make check             # verify tools, image, and licenses
make infra             # create vault-1, vault-2, vault-3 VMs (Terraform)

# Phase 2 — replace the five shell script steps with one playbook
ansible-playbook ansible/site.yml

# Or run individual phases via tags
ansible-playbook ansible/site.yml --tags tls
ansible-playbook ansible/site.yml --tags install
ansible-playbook ansible/site.yml --tags license
ansible-playbook ansible/site.yml --tags configure
ansible-playbook ansible/site.yml --tags bootstrap

make validate          # cluster health check (uses vault CLI, same for both paths)
make platform          # apply Terraform platform layer
make platform-validate # drift check
```

> **Note:** the Ansible path requires your SSH public key to be present in
> `terraform/infra/cloud-init/rhel.yaml` under `ssh_authorized_keys`. This is
> already configured for the current setup. On a fresh clone, replace the key
> value with your own `~/.ssh/id_ed25519.pub` before running `make infra`.

---

## Make targets

| Target | Description |
|---|---|
| `check` | Prerequisite and license validation |
| `infra-plan` | Terraform plan for VM infrastructure |
| `infra` | Create or update VMs |
| `rhel-prepare` | Register RHEL nodes with RHSM and install `firewalld` |
| `rhel-unregister` | Unregister nodes from RHSM before destroy |
| `infra-validate` | Verify Terraform state and VM reachability |
| `tls` | Generate and distribute TLS material (shell path) |
| `install` | Install Vault Enterprise binary (shell path) |
| `license` | Push Vault license to all nodes (shell path) |
| `configure` | Write Vault config and start the service (shell path) |
| `bootstrap` | Initialize, join Raft, unseal, create platform token (shell path) |
| `validate` | Live cluster health check |
| `platform-plan` | Terraform plan for Vault configuration |
| `platform` | Apply Vault configuration |
| `platform-validate` | Drift detection for Vault configuration |
| `failover-help` | Print the manual failover acceptance test |
| `destroy` | Destroy VMs (Terraform interactive confirm) |

---

## Ansible layout

```
ansible/
├── ansible.cfg                    # inventory, ssh_args, interpreter defaults
├── site.yml                       # top-level playbook (all roles, tagged)
├── inventory/
│   └── terraform.py               # dynamic inventory from terraform output
├── group_vars/
│   └── vault.yml                  # version, paths, ports, secrets locations
└── roles/
    ├── tls/                       # generate CA + certs locally, push to nodes
    ├── vault_install/             # binary, user, dirs, firewall, swap
    ├── vault_license/             # push .hclic (no_log throughout)
    ├── vault_configure/           # vault.hcl template, systemd unit, /etc/hosts
    └── vault_bootstrap/           # init, raft join, unseal, policy, token
```

Check connectivity at any time:

```bash
ansible vault -m ping --private-key ~/.ssh/id_ed25519 -u ubuntu
```

---

## Secrets layout

```
.secrets/              # mode 700, never committed
├── keys/
│   ├── vault.hclic    # Vault Enterprise license
│   └── terraform.hclic
├── tls/               # CA and per-node certs (generated locally)
├── vault-init.json    # root token + unseal keys — back this up
└── platform-token     # scoped Terraform token
```

---

## Override reference

| Variable | Default | Purpose |
|---|---|---|
| `TF_VAR_image_path` | `/Users/Shared/rhel-9.8-aarch64-kvm.qcow2` | RHEL qcow2 image |
| `VAULT_LICENSE_FILE` | `.secrets/keys/vault.hclic` | Vault license path (shell + Ansible) |
| `TF_LICENSE_PATH` | `.secrets/keys/terraform.hclic` | Terraform license path |
| `VAULT_VERSION` | `2.1.0+ent` | Vault Enterprise version to install |
| `RHSM_ORG` + `RHSM_ACTIVATION_KEY` | — | Required only for `make rhel-prepare` |

---

## License

[GPLv3](LICENSE)
