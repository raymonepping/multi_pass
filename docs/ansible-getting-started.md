# Ansible — Getting Started

This guide covers everything you need to run, understand, and extend the
Ansible layer of this project. It assumes `make infra` has completed and
the VMs are reachable.

---

## Prerequisites

```bash
brew install ansible
ansible-galaxy collection install community.crypto ansible.posix
```

Verify:

```bash
ansible --version          # should show ansible-core 2.15+
ansible-galaxy collection list | grep -E "crypto|posix"
```

---

## 1. Verify connectivity

Before running any playbook, confirm Ansible can reach all three nodes:

```bash
ansible vault -m ping --private-key ~/.ssh/id_ed25519 -u ubuntu
```

All three should return `pong`. If any fail, see the
[SSH troubleshooting section](#ssh-troubleshooting) below.

---

## 2. Check what Ansible sees

```bash
# Inventory — hosts and their IPs (read live from terraform output)
ansible-inventory --list
ansible-inventory --graph

# OS, hostname, IP of all nodes
ansible vault -m setup \
  -a "filter=ansible_hostname,ansible_default_ipv4,ansible_distribution*" \
  --private-key ~/.ssh/id_ed25519 -u ubuntu

# Is Vault running?
ansible vault -m systemd -a "name=vault" \
  --private-key ~/.ssh/id_ed25519 -u ubuntu \
  | grep -E "ActiveState|SubState"

# What version is installed?
ansible vault -m command -a "/usr/local/bin/vault version" \
  --private-key ~/.ssh/id_ed25519 -u ubuntu
```

---

## 3. Run the full playbook

Runs all five roles in order against all three nodes:

```bash
ansible-playbook ansible/site.yml
```

Everything is idempotent — rerunning produces `ok` results where nothing
has changed and `changed` only where something actually differs.

---

## 4. Run a single role

Each role is tagged. Use `--tags` to run only what you need:

```bash
ansible-playbook ansible/site.yml --tags tls        # generate/push certs
ansible-playbook ansible/site.yml --tags install    # Vault binary
ansible-playbook ansible/site.yml --tags license    # push vault.hclic
ansible-playbook ansible/site.yml --tags configure  # vault.hcl + service
ansible-playbook ansible/site.yml --tags bootstrap  # init, unseal, token
```

---

## 5. Dry-run (check mode)

See what *would* change without touching anything:

```bash
ansible-playbook ansible/site.yml --check --diff
```

- `ok` — already in the desired state
- `changed` — would be modified
- `skipped` — condition not met (e.g. CA already exists)

This is the Ansible equivalent of `terraform plan`.

---

## 6. Configuration reference

### `ansible.cfg`

Located at the repo root. Key settings:

| Setting | Value | Purpose |
|---|---|---|
| `inventory` | `ansible/inventory/terraform.py` | Dynamic inventory from Terraform |
| `roles_path` | `ansible/roles` | Where roles are found |
| `stdout_callback` | `ansible.builtin.default` | Human-readable YAML output |
| `result_format` | `yaml` | Task output format |
| `interpreter_python` | `/usr/bin/python3.9` | Python on the RHEL nodes |
| `ssh_args` | `-F /dev/null ...` | Bypasses macOS `~/.ssh/config` |
| `become` | `true` | All remote tasks run as root via sudo |
| `pipelining` | `true` | Faster SSH — fewer round trips |

### `ansible/group_vars/vault.yml`

Single source of truth for all variables. Key ones to know:

| Variable | Default | Notes |
|---|---|---|
| `vault_version` | `2.1.0+ent` | Keep in sync with `scripts/common.sh` |
| `vault_archive_sha256` | `a0fbf...` | Must match the version above |
| `vault_arch` | `linux_arm64` | RHEL on ARM64 (Multipass on Apple Silicon) |
| `vault_leader` | `vault-1` | Node used for init, Raft joins, policy uploads |
| `key_shares` | `3` | Shamir unseal shares |
| `key_threshold` | `2` | Unseal threshold |
| `secrets_dir` | `../.secrets` | Local secrets directory (never committed) |

To change the Vault version, update both `vault_version` and
`vault_archive_sha256` in `group_vars/vault.yml` **and** `VAULT_VERSION`/
`VAULT_ARCHIVE_SHA256` in `scripts/common.sh`.

---

## 7. Dynamic inventory

The inventory script at [`ansible/inventory/terraform.py`](../ansible/inventory/terraform.py)
reads `terraform output` live every time Ansible runs. There is no static
hosts file to maintain — IPs update automatically when VMs are rebuilt.

```bash
# See the raw inventory JSON
python3 ansible/inventory/terraform.py

# Condensed host list
ansible-inventory --graph
```

The script requires `terraform/infra/terraform.tfstate` to exist (i.e.
`make infra` must have run). If the state is absent, it exits with a clear
error.

---

## 8. Role reference

### `roles/tls`

Generates a CA and per-node certificates **locally** on the control machine
(your Mac), then pushes the material to each node. Vault is restarted if
any certificate changes.

- CA lives at `.secrets/tls/ca.crt` / `ca.key`
- Node certs at `.secrets/tls/vault-{1,2,3}.crt` / `.key`
- Regenerates a node cert only if the IP SAN is missing or the cert is expired
- Uses `community.crypto` modules — requires the collection to be installed

### `roles/vault_install`

Downloads the Vault Enterprise zip to `.cache/` once (verified by SHA-256),
unpacks it, and installs the binary on all nodes. Also creates the `vault`
system user, required directories, opens firewall ports, and disables swap.

- Download happens on localhost, install happens on each remote node
- Idempotent — skips the download if the archive is already cached and verified

### `roles/vault_license`

Copies `.secrets/keys/vault.hclic` to `/opt/vault/vault.hclic` on each node
with `owner: root`, `group: vault`, `mode: 0640`. The file content is never
logged (`no_log: true`). Override the source path with `VAULT_LICENSE_FILE`.

### `roles/vault_configure`

Writes `vault.hcl` from the Jinja2 template at
[`roles/vault_configure/templates/vault.hcl.j2`](../ansible/roles/vault_configure/templates/vault.hcl.j2),
installs the systemd unit, updates `/etc/hosts` with peer addresses, and
ensures the service is running.

To change Vault's configuration (e.g. add a telemetry stanza), edit the
template and rerun `--tags configure`.

### `roles/vault_bootstrap`

The most sensitive role. Uses the Vault HTTP API via `ansible.builtin.uri`
(`delegate_to: localhost`, `become: false`) to:

1. Initialize vault-1 (`operator init`) — only on first run
2. Write init material to `.secrets/vault-init.json` (mode 0600, localhost only)
3. Check seal status and unseal each node — skipped if already unsealed
4. Join vault-2 and vault-3 to the Raft cluster — skipped if already joined
5. Upload the `lab-platform-admin` policy
6. Create or reuse the platform token at `.secrets/platform-token`
7. Verify three Raft voters

All tasks that touch unseal keys or tokens have `no_log: true`.

---

## 9. Extending Ansible

### Add a new task to an existing role

Edit the relevant `tasks/main.yml`. Follow the pattern:
- Remote tasks: no `delegate_to`, `become` inherited from play
- Local tasks: `delegate_to: localhost`, `become: false`
- Secret tasks: `no_log: true`

### Add a new role

```bash
mkdir -p ansible/roles/my_role/{tasks,handlers,templates}
touch ansible/roles/my_role/tasks/main.yml
```

Register it in [`ansible/site.yml`](../ansible/site.yml) with a tag:

```yaml
- role: my_role
  tags: my_role
```

### Add a new variable

Add it to [`ansible/group_vars/vault.yml`](../ansible/group_vars/vault.yml).
Never hardcode paths or version numbers inside a role task file.

---

## SSH troubleshooting

**`pong` not returned / connection refused**

Check the VM is running:
```bash
multipass list
```

Inject your key if needed:
```bash
multipass exec vault-1 -- bash -c \
  "echo '$(cat ~/.ssh/id_ed25519.pub)' >> /home/ubuntu/.ssh/authorized_keys"
```

**`UseKeychain` error**

`ansible.cfg` already sets `ssh_args = -F /dev/null` to bypass
`~/.ssh/config`. Confirm the config file is being picked up:
```bash
ansible --version | grep "config file"
```

**`community.crypto` module not found**

```bash
ansible-galaxy collection install community.crypto ansible.posix
```
