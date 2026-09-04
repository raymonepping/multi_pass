# Shell Scripts — Getting Started

This guide covers the shell script layer of the project: what each script
does, how to use the Make targets, how to resume after a failure, and where
the key files live. These scripts are the default Phase 2 path — use them
when you want to step through each stage individually or when learning how
the cluster is built.

---

## Prerequisites

All of these must be on your `PATH`:

```bash
make check
```

`make check` verifies: `terraform`, `multipass`, `vault` CLI, `jq`,
`openssl`, `curl`, `unzip`, `shasum`, and `rg` (ripgrep). It also confirms
the RHEL qcow2 image exists and both license files are in place.

---

## 1. Licenses

Place your licenses before running anything:

```
.secrets/keys/vault.hclic       ← Vault Enterprise license
.secrets/keys/terraform.hclic   ← Terraform Enterprise license
```

Both paths are the default — `scripts/common.sh` exports them automatically.
Override either with an environment variable:

```bash
export VAULT_LICENSE_FILE=/path/to/vault.hclic
export TF_LICENSE_PATH=/path/to/terraform.hclic
```

---

## 2. The full sequence

Run these Make targets in order. Each one is idempotent — safe to rerun.

```bash
make check       # 1. prerequisites and license validation
make infra       # 2. create vault-1, vault-2, vault-3 VMs
make tls         # 3. generate CA + node certs, push to guests
make install     # 4. install Vault Enterprise binary on all nodes
make license     # 5. push vault.hclic to all nodes
make configure   # 6. write vault.hcl, start the service
make bootstrap   # 7. operator init, Raft join, unseal, platform token
make validate    # 8. cluster health check
make platform    # 9. apply Vault config via Terraform
make platform-validate  # 10. confirm no drift
```

---

## 3. Script reference

### `scripts/check.sh` → `make check`

Verifies all required CLI tools are present, the RHEL qcow2 image exists,
both license files exist (never reads their contents), and no sensitive files
are tracked by Git. Also runs `terraform fmt -check` on both Terraform
directories.

---

### `scripts/tls.sh` → `make tls`

Generates a local CA and per-node TLS certificates, then distributes them
to each VM.

**What it creates locally** (in `.secrets/tls/`, never committed):
```
ca.key / ca.crt          10-year self-signed CA
vault-1.key / .crt       825-day node cert, SANs: vault-1, IP, localhost
vault-2.key / .crt
vault-3.key / .crt
```

**Idempotency:** skips a node cert if it already exists, hasn't expired,
and contains the current VM IP in its SAN. Delete `.secrets/tls/` and rerun
to force full regeneration.

**Re-run when:** a VM IP changes, a cert is about to expire, or the CA
is replaced.

```bash
make tls            # generate and push
make tls configure  # push + restart service (required if certs changed)
```

---

### `scripts/install.sh` → `make install`

Downloads the Vault Enterprise binary to `.cache/` (verified by SHA-256),
then runs `scripts/install-vault-guest.sh` on each node, which:

- Creates the `vault` system user
- Installs the binary to `/usr/local/bin/vault`
- Creates `/etc/vault.d`, `/opt/vault/data`, `/opt/vault/tls`
- Opens firewall ports 8200/tcp and 8201/tcp
- Disables swap

**Idempotency:** the archive is cached after the first download. The guest
script is safe to rerun.

**Key variables** (in `scripts/common.sh`):
```bash
VAULT_VERSION="2.1.0+ent"
VAULT_ARCHIVE_SHA256="a0fbf..."
```

---

### `scripts/license.sh` → `make license`

Pushes the Vault license to `/opt/vault/vault.hclic` on each node with
permissions `root:vault 0640`. The license content is never printed.

**Input sources** (exactly one must be set):

| Variable | Description |
|---|---|
| `VAULT_LICENSE_FILE` | Path to a raw `.hclic` file (default: `.secrets/keys/vault.hclic`) |
| `VAULT_LICENSE_ENV_FILE` | Path to a file containing `VAULT_LICENSE=<value>` |
| `VAULT_LICENSE` | The license string directly in the environment |

Since `scripts/common.sh` sets `VAULT_LICENSE_FILE` to the default path,
`make license` works with no extra configuration as long as the file exists.

**Re-run when:** the license expires or is replaced.

```bash
make license            # push the license
make license configure  # push + restart (required after license change)
```

---

### `scripts/configure.sh` → `make configure`

Writes `vault.hcl` and the systemd unit to each node, updates `/etc/hosts`
for peer name resolution, and starts the Vault service.

**What it pushes to each node:**

| File | Destination | Owner | Mode |
|---|---|---|---|
| `vault.hcl` (from template) | `/etc/vault.d/vault.hcl` | `root:vault` | `0640` |
| `vault.service` | `/etc/systemd/system/vault.service` | `root:root` | `0644` |
| `ca.crt` | `/opt/vault/tls/ca.crt` | `vault:vault` | `0644` |
| `server.crt` | `/opt/vault/tls/server.crt` | `vault:vault` | `0644` |
| `server.key` | `/opt/vault/tls/server.key` | `vault:vault` | `0600` |

The template is at [`templates/vault/vault.hcl.tpl`](../templates/vault/vault.hcl.tpl).
`@NODE@` and `@IP@` are substituted per node.

**Re-run when:** the configuration template changes, IPs change, or certs
are rotated.

---

### `scripts/bootstrap.sh` → `make bootstrap`

The most sensitive script — handles operator init, Raft joining, unsealing,
and platform token creation.

**What it does:**

1. Checks if vault-1 is initialized. If not, runs `vault operator init`
   and writes the output to `.secrets/vault-init.json` (mode 0600).
2. Unseals vault-1 with two keys from the init file.
3. For vault-2 and vault-3: joins each to the Raft cluster, then unseals.
4. Uploads the `lab-platform-admin` policy from `policies/platform-admin.hcl`.
5. Creates a scoped platform token and writes it to `.secrets/platform-token`.
6. Verifies all three nodes are Raft voters.

**Re-run safety:** the script checks whether vault-1 is already initialized
before touching the init file. If the init file already exists but vault-1
reports uninitialized, it stops with an error rather than overwriting recovery
material.

**Key files written:**

| File | Contents | Mode |
|---|---|---|
| `.secrets/vault-init.json` | Root token + unseal keys | `0600` |
| `.secrets/platform-token` | Scoped Terraform token | `0600` |

**Back up `.secrets/vault-init.json` immediately after the first run.**
It cannot be recovered if lost.

---

### `scripts/validate.sh` → `make validate`

Connects to all three nodes via the Vault API and verifies:

- Service is active (`systemctl is-active vault`)
- SELinux is Enforcing
- Swap is off
- Firewall ports 8200 and 8201 are open
- Node is initialized and unsealed
- One node is `active`, two are `standby` / `performance_standby`
- Three Raft voters
- License is autoloaded and not expired

Run this at any time to confirm cluster health.

---

### `scripts/platform.sh` → `make platform / platform-plan / platform-validate`

Wrapper that injects the three required Vault environment variables and
delegates to `terraform -chdir=terraform/platform`. Not meant to be called
directly — use the Make targets.

```bash
make platform-plan      # terraform validate + plan
make platform           # terraform validate + apply -auto-approve
make platform-validate  # terraform validate + plan -detailed-exitcode
```

---

## 4. `scripts/common.sh`

Sourced by every script. Defines all shared variables and helper functions.
Key items:

```bash
ROOT_DIR          # repo root (derived from script location)
SECRETS_DIR       # .secrets/
TLS_DIR           # .secrets/tls/
KEYS_DIR          # .secrets/keys/
INIT_FILE         # .secrets/vault-init.json
PLATFORM_TOKEN_FILE  # .secrets/platform-token
NODES             # (vault-1 vault-2 vault-3)
VAULT_VERSION     # 2.1.0+ent
VAULT_LICENSE_FILE   # .secrets/keys/vault.hclic  (default, overridable)
TF_LICENSE_PATH      # .secrets/keys/terraform.hclic  (default, overridable)
```

Helper functions:

| Function | Purpose |
|---|---|
| `die "message"` | Print error to stderr and exit 1 |
| `info "message"` | Print `==> message` to stdout |
| `require_cmd name` | Exit if a command is not on PATH |
| `node_ip vault-N` | Look up a node's IP from Terraform output |
| `vault_cli vault-N <args>` | Run `vault` with the correct `VAULT_ADDR` and `VAULT_CACERT` |
| `root_token` | Read the root token from `.secrets/vault-init.json` |
| `run_with_root_token vault-N <args>` | Run `vault` with root token set |
| `require_managed_nodes` | Verify all three nodes exist in TF state and are reachable |

---

## 5. Overrides

All key values can be overridden without editing files:

```bash
# Use a different RHEL image
export TF_VAR_image_path=/your/rhel.qcow2

# Use a different Vault version
export VAULT_VERSION=2.2.0+ent
export VAULT_ARCHIVE_SHA256=<sha256-of-new-archive>

# Use a different license path
export VAULT_LICENSE_FILE=/secure/vault.hclic

# Use a different Terraform license
export TF_LICENSE_PATH=/secure/terraform.hclic

# Use a different RHSM registration
export RHSM_ORG=your-org
export RHSM_ACTIVATION_KEY=your-key
```

---

## 6. Resume after failure

Every script exits immediately on error (`set -euo pipefail`) and prints the
failing step. Fix the reported problem and rerun the same `make` target.

Common recovery commands:

```bash
# Node sealed after restart — unseal with two keys
KEY0=$(jq -r '.unseal_keys_b64[0]' .secrets/vault-init.json)
KEY1=$(jq -r '.unseal_keys_b64[1]' .secrets/vault-init.json)
VAULT_ADDR="https://<node-ip>:8200" vault operator unseal "${KEY0}"
VAULT_ADDR="https://<node-ip>:8200" vault operator unseal "${KEY1}"

# Confirm health after recovery
make validate
```

See [`docs/operations.md`](operations.md) for the full list of resume points.
