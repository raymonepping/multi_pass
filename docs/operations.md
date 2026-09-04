# Operations

## Resume points

Every script and every Ansible role is idempotent and safe to rerun. If
execution stops at any step, fix the reported error and rerun that Make target
or playbook tag. Guards at the start of each script and role prevent
double-initialisation and skip work that is already complete.

### Infrastructure

- **Terraform state absent:** run `make infra` from scratch.
- **VM unreachable after creation:** run `make infra-validate`. It checks
  cloud-init completion, SELinux enforcing mode, ARM64 architecture, RHEL 9
  OS, and `firewalld` presence on every node.
- **Missing `firewalld`:** export `RHSM_ORG` and `RHSM_ACTIVATION_KEY`, then
  run `make rhel-prepare`. Alternatively, rebuild the source qcow2 with
  `firewalld` preinstalled. Do not disable the firewall gate or mix packages
  from a different distribution.
- **RHSM reports `Name or service not known`:** rerun `make rhel-prepare`. It
  distinguishes broken DNS from a broken Multipass NAT path and persists the
  configurable `RHEL_DNS_SERVERS` through NetworkManager when only DNS is
  affected.

### TLS

- **Missing or expired CA:** for an initialized cluster, restore its existing
  CA and private key from backup. The Ansible role refuses an incomplete pair
  rather than silently generating a replacement. For a genuinely new lab,
  `make ansible-converge` creates a 10-year CA and node certificates.
- **Changed VM IP:** rerun `make tls configure` (shell fallback) or
  `make ansible-converge` (normal path).
  Node certificates are regenerated only when the current IP SAN is absent from
  the existing cert, so unchanged nodes are skipped. The configure step must
  follow to push the new material to the guests and restart the service.

### Vault binary and license

- **Binary absent on a node:** rerun `make install` or
  `make ansible-converge`. Idempotent — skips nodes
  where the correct version is already present.
- **Missing Vault license:** place the raw `.hclic` file at
  `.secrets/keys/vault.hclic` (default) or export `VAULT_LICENSE_FILE`
  pointing to another path, then rerun `make license` or
  `make ansible-converge`.
- **License parse error (`expected integer`):** the selected file is not a raw
  HashiCorp license (often a placeholder or env-wrapped value). Point
  `VAULT_LICENSE_ENV_FILE` at an ignored environment file containing
  `VAULT_LICENSE=` and rerun `make license`. The value is extracted into a
  temporary mode-`0600` file and never printed. (Shell path only — the Ansible
  role reads the raw file directly.)
- **Expired/invalid license:** replace `.secrets/keys/vault.hclic` and rerun
  `make license configure` or `make ansible-converge`.

### Vault bootstrap

- **Sealed node after restart:** run `make ansible-converge`. The bootstrap role
  detects sealed nodes and submits the configured threshold from the existing
  ignored `.secrets/vault-init.json`. It never initializes an existing cluster.
  Manual recovery remains available using two distinct keys:

  ```sh
  KEY0=$(jq -r '.unseal_keys_b64[0]' .secrets/vault-init.json)
  KEY1=$(jq -r '.unseal_keys_b64[1]' .secrets/vault-init.json)
  VAULT_ADDR="https://<node-ip>:8200" vault operator unseal "${KEY0}"
  VAULT_ADDR="https://<node-ip>:8200" vault operator unseal "${KEY1}"
  ```

  The cluster never auto-unseals on boot because this lab uses Shamir seal.
  Never paste keys into shell history on a shared machine.

- **Lost `.secrets/vault-init.json`:** do not reinitialise or destroy the
  cluster. Restore the file from your secure backup — it is the only copy of
  the root token and unseal keys.
- **Expired platform token:** rerun `make bootstrap` (shell fallback) or
  `make ansible-converge` (normal path). Both
  detect that the existing token is invalid and create a new one.

### Ansible-specific

- **SSH connection refused:** run `make ansible-ssh`. It creates or reuses the
  dedicated ignored lab key, offers the scoped in-place public-key migration,
  records host keys, and verifies all three connections. It never uses or
  modifies the user's normal SSH identity.
- **SSH host key changed:** first verify the VM was intentionally recreated.
  Then run `CONFIRM_ANSIBLE_HOST_KEY_CHANGE=yes make ansible-ssh`. An
  unconfirmed change fails closed.
- **`sudo: a password is required` on a `delegate_to: localhost` task:** the
  play-level `become: true` is inherited by local tasks. All `delegate_to:
  localhost` tasks in the roles already carry `become: false` to prevent this.
  If you see it after modifying a role, add `become: false` to the affected task.
- **`UseKeychain` SSH error:** `ansible.cfg` sets `ssh_args = -F /dev/null` to
  bypass `~/.ssh/config` while retaining strict project-local host-key
  verification. If you see this error,
  confirm `ansible.cfg` is being picked up (`ansible --version` should show
  the config file path).
- **Ansible collection missing:** install the exact pinned dependencies:
  ```sh
  make ansible-deps
  ```
### Terraform platform layer

- **Permission denied on mounts:** the `lab-platform-admin` policy must cover
  `+/sys/mounts/*` (child namespace paths) in addition to `sys/mounts/*`. The
  current `policies/platform-admin.hcl` already includes this; if you have
  modified the policy, rerun `make bootstrap` to re-upload it.
- **Platform drift detected:** `make platform-validate` reports changes that
  exist in Vault but not in Terraform state (manual changes). Reconcile by
  either importing the resource or removing it and rerunning `make platform`.

---

## Manual failover acceptance test

This test is deliberately not automated because it changes live cluster state.

1. Run `make validate` and note the node whose `ha_role` is `active`.
2. Stop Vault only on that node:

   ```sh
   multipass exec <active-node> -- sudo systemctl stop vault
   ```

3. Wait 5–10 seconds, then check the remaining two nodes:

   ```sh
   # repeat for both remaining nodes
   VAULT_ADDR="https://<node-ip>:8200" VAULT_CACERT=".secrets/tls/ca.crt" \
     vault status
   ```

   Confirm exactly one node now shows `ha_role: active`.

4. Start the original node:

   ```sh
   multipass exec <active-node> -- sudo systemctl start vault
   ```

5. Unseal the restarted node with any two distinct keys from
   `.secrets/vault-init.json` (see the unseal steps above).

6. Run `make validate` and confirm one active, two standby, and three voters.

---

## Day-2 Vault configuration changes

All Vault configuration — namespaces, secret engine mounts, auth methods, and
policies — is managed by the Terraform platform layer. To make a change:

1. Edit `terraform/platform/` (variables, `main.tf`, or add a new `.tf` file).
2. Run `make platform-plan` to review the diff.
3. Run `make platform` to apply it.
4. Run `make platform-validate` to confirm the plan is clean.

Do not make configuration changes manually via the Vault CLI or UI unless you
intend to import them into Terraform state afterwards. Manual changes will
show as drift in `make platform-validate`.

---

## Teardown

`make destroy` invokes Terraform's normal interactive destroy confirmation and
targets only the three resources owned by `terraform/infra`. It does not
delete unrelated Multipass instances. Local `.secrets` and `.cache` artifacts
are retained — their deletion is a separate, explicit operator decision.

RHEL registration is external state and Terraform cannot remove its Red Hat
inventory records. If the lab nodes were registered and should be removed from
Subscription Management, do this while they still exist:

```sh
CONFIRM_RHSM_UNREGISTER=yes make rhel-unregister
make destroy
```

Unregistration is never automatic. It removes the guest identity and access to
protected Red Hat content, updates, and security patches. The unregister target
is restricted to the three VM names resolved from the infrastructure state and
skips guests that have no registered identity.

After `make destroy`, reset the platform and Ansible orchestration state files
before reprovisioning:

```sh
rm -f terraform/platform/terraform.tfstate terraform/platform/terraform.tfstate.backup
rm -f terraform/ansible/terraform.tfstate terraform/ansible/terraform.tfstate.backup
```

The Ansible roles are stateless — no cleanup needed. On the next `make lab`
run, `terraform/infra` writes fresh IP addresses into state, `terraform/ansible`
reads them, and Ansible converges the new nodes.
