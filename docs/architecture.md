# Architecture

This document describes the complete structure of the Vault lab: what each
layer owns, how the layers communicate, and why the boundaries are drawn where
they are.

---

## Overview

```text
                      macOS / Apple Silicon
                               │
                    ┌──────────▼──────────┐
                    │  Terraform: infra   │  terraform/infra
                    │  todoroff/multipass │
                    └──────────┬──────────┘
                               │  ansible_nodes output
                               │  vault_api_addresses output
                    ┌──────────▼──────────┐
                    │ Terraform: ansible  │  terraform/ansible
                    │  ansible/ansible    │
                    └──────────┬──────────┘
                               │  ansible_playbook resource
                    ┌──────────▼──────────┐
                    │  Ansible site.yml   │  ansible/
                    │  seven roles        │
                    └──────────┬──────────┘
                               │  .secrets/platform-token
                    ┌──────────▼──────────┐
                    │ Terraform: platform │  terraform/platform
                    │  hashicorp/vault    │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  Vault Enterprise   │
                    │  Integrated Storage │
                    │  three-node Raft    │
                    └─────────────────────┘
```

The primary operator interface is:

```bash
make lab
```

---

## Layers and ownership

### Terraform: infrastructure (`terraform/infra`)

**Providers:** `todoroff/multipass 1.7.1`, `hashicorp/local 2.5.3`

**Owns:**
- Three Multipass VMs (`vault-1`, `vault-2`, `vault-3`) on RHEL 9 ARM64
- Cloud-init rendered from `cloud-init/rhel.yaml.tftpl` — injects the
  dedicated Ansible SSH public key only; no credentials
- Non-secret topology outputs consumed by downstream roots

**Outputs:**

| Output | Type | Used by |
|---|---|---|
| `node_names` | `list(string)` | Scripts, validation |
| `node_ipv4` | `map(string)` | Scripts, `platform` root |
| `ansible_nodes` | `map(object)` | `ansible` root |
| `vault_api_addresses` | `map(string)` | `platform` root |

**Key constraint:** `cloud_init_file` uses `lifecycle { ignore_changes = [...] }`
because cloud-init is immutable after VM creation. The dedicated SSH key is
injected into existing VMs out-of-band by `scripts/ansible-ssh.sh`.

---

### Terraform: Ansible orchestration (`terraform/ansible`)

**Providers:** `ansible/ansible 1.5.0`

**Owns:**
- Supervision of the Ansible convergence run
- Propagation of Ansible failure into the Terraform graph

**How it works:**

The root reads `ansible_nodes` from infra state via `terraform_remote_state`
and passes the full node topology as a JSON `extra_var` to the
`ansible_playbook` resource. No inventory file is used. The playbook
`ansible/terraform.yml` builds the `vault` group in memory during its first
play, then imports `ansible/site.yml`.

```hcl
resource "ansible_playbook" "vault_lab" {
  playbook   = ".../ansible/terraform.yml"
  replayable = false

  extra_vars = {
    vault_nodes_json         = jsonencode(ansible_nodes)
    ansible_private_key_file = ".secrets/ansible/id_ed25519"
    ansible_known_hosts_file = ".secrets/ansible/known_hosts"
    automation_digest        = sha256(all automation files)
  }
}
```

**Dependency graph:**

```text
data.terraform_remote_state.deployment
             ↓
    ansible_playbook.vault_lab
```

**Re-convergence trigger:** `automation_digest` is a SHA-256 hash of every
file under `ansible/`, `templates/`, and `policies/platform-admin.hcl`. Any
change to automation content causes the resource to be replaced on the next
apply, which re-runs the playbook. No manual `-replace` flag is needed.

**Why `replayable = false`:** the playbook is idempotent, but re-running it on
every `terraform plan` would be slow and noisy. `make ansible-converge`
explicitly replaces the resource when a re-run is requested.

---

### Ansible convergence (`ansible/`)

**Collections:** `community.crypto 3.3.0`, `ansible.posix 2.2.2`

**Entry point:** `ansible/terraform.yml` (called by the Terraform provider),
or `ansible/site.yml` directly for manual runs.

**Roles, in order:**

| Role | Responsibility |
|---|---|
| `rhel_prepare` | Assert RHEL 9 ARM64 with SELinux enforcing; repair DNS; enable firewalld |
| `vault_install` | Download and verify pinned Vault binary; create service account and directories; open ports 8200/8201; disable swap |
| `tls` | Create a local CA (10-year) and per-node certs (825-day, IP SANs); distribute to guests; idempotent on unchanged IPs |
| `vault_configure` | Write `vault.hcl`, peer `/etc/hosts` entries, hardened systemd unit |
| `vault_license` | Install raw `.hclic` with `root:vault 0640`; `no_log: true` throughout |
| `vault_bootstrap` | Initialize (once only), join followers before unsealing, unseal all nodes, create/reuse platform token |
| `vault_validate` | Assert service active, initialized, unsealed, three Raft voters, license valid, TLS reachable |

**Contract:** if `vault_validate` passes, `ansible_playbook.vault_lab` exits
zero and Terraform continues. If any assertion fails, Terraform stops and the
platform layer does not run.

**SSH:** Ansible uses exclusively `.secrets/ansible/id_ed25519`. The user's
`~/.ssh/config` is bypassed with `-F /dev/null` to prevent macOS-specific
`UseKeychain` settings from interfering. Host keys are stored in
`.secrets/ansible/known_hosts` with strict checking enforced.

---

### Terraform: platform (`terraform/platform`)

**Providers:** `hashicorp/vault 5.11.0`

**Owns:**
- Vault Enterprise namespaces
- Secret engine mounts
- (Policy upload is handled by Ansible bootstrap; it is not duplicated here)

**Authentication:** `scripts/platform.sh` exports `VAULT_CACERT` and reads
`VAULT_TOKEN` from `.secrets/platform-token`. The token is never a Terraform
variable, never in state.

**Why separate from `terraform/ansible`:** Terraform provider configuration is
evaluated before the apply graph runs. The platform token does not exist until
Ansible bootstrap completes. Putting the Vault provider and `ansible_playbook`
in the same root would create an unresolvable dependency.

**Default resources:**

```text
engineering/         (namespace)
├── kv/              (KV v2 mount)
└── transit/         (Transit mount)

operations/          (namespace)
└── pki/             (PKI mount — CA not generated by Terraform)
```

---

## Secret boundary

Terraform state is readable by anyone with filesystem access. Nothing secret
enters it.

| Value | Where it lives | What sees it |
|---|---|---|
| Root token + unseal keys | `.secrets/vault-init.json` | Ansible `vault_bootstrap` role only (`no_log: true`) |
| Platform token | `.secrets/platform-token` | `scripts/platform.sh` (env var, never Terraform input) |
| Vault license | `.secrets/keys/vault.hclic` | Ansible `vault_license` role only (`no_log: true`) |
| TLS private keys | `.secrets/tls/` | Ansible `tls` role only |
| SSH private key | `.secrets/ansible/id_ed25519` | Ansible process (path passed as `extra_var`, never content) |

`make state-secret-check` scans all `terraform.tfstate` files for known
secret values without printing them.

---

## Data flow between roots

```text
terraform/infra state
  └── ansible_nodes: {vault-1: {ansible_host, vault_role}, ...}
  └── vault_api_addresses: {vault-1: "https://IP:8200", ...}
        │
        │  terraform_remote_state (read-only)
        ▼
terraform/ansible
  └── passes vault_nodes_json (JSON string) to ansible_playbook extra_vars
        │
        │  ansible-playbook subprocess
        ▼
ansible/terraform.yml
  └── builds vault group in memory (add_host)
  └── imports site.yml
        │
        │  SSH (dedicated key + project known_hosts)
        ▼
vault-1, vault-2, vault-3
  └── writes .secrets/platform-token on first bootstrap
        │
        │  file read by scripts/platform.sh
        ▼
terraform/platform
  └── vault_namespace, vault_mount resources
```

---

## `make lab` phase sequence

```text
Phase                             Script / command
─────────────────────────────────────────────────────────────────────────
check                             scripts/check.sh
ansible-deps                      scripts/ansible-deps.sh
ansible-ssh prepare               scripts/ansible-ssh.sh prepare
terraform/infra apply             make deployment
ansible-ssh all                   scripts/ansible-ssh.sh all
terraform/ansible apply           scripts/ansible-run.sh apply
  └── ansible_playbook.vault_lab
        └── ansible/terraform.yml
              └── ansible/site.yml  (seven roles)
validate                          scripts/validate.sh
terraform/platform apply          scripts/platform.sh apply
ansible-run validate              scripts/ansible-run.sh validate
platform validate                 scripts/platform.sh validate
state-secret-check                scripts/check-state-secrets.sh
─────────────────────────────────────────────────────────────────────────
```

Each phase is independently resumable. If a phase fails, fix the reported
error and rerun `make lab` or the individual target.

---

## Provider version pins

| Root | Provider | Version |
|---|---|---|
| `terraform/infra` | `todoroff/multipass` | `1.7.1` |
| `terraform/infra` | `hashicorp/local` | `2.5.3` |
| `terraform/ansible` | `ansible/ansible` | `1.5.0` |
| `terraform/platform` | `hashicorp/vault` | `5.11.0` |

All lockfiles are committed. Provider downloads are cached in
`.terraform/` (gitignored).

---

## Replacing the infrastructure substrate

The Vault and Ansible layers have no direct dependency on Multipass.

To run on a different infrastructure provider:

1. Replace `terraform/infra` with a root that creates three RHEL 9 ARM64
   machines and emits the same four outputs (`node_names`, `node_ipv4`,
   `ansible_nodes`, `vault_api_addresses`).
2. Run `make ansible-ssh` to authorize the dedicated key and record host keys.
3. Run the remaining phases as normal.

The `terraform/ansible` and `terraform/platform` roots are unchanged.
The Ansible roles are unchanged. The Vault cluster is unchanged.

That is the portability guarantee the architecture was designed to provide.
