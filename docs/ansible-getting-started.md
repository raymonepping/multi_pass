# Ansible provider workflow

Ansible is launched and supervised by Terraform. The primary entry point is:

```bash
make ansible-converge
```

The command applies `terraform/ansible`. Its `ansible_playbook.vault_lab`
resource reads the non-secret `ansible_nodes` output from `terraform/infra`,
runs `ansible/terraform.yml`, waits for completion, and fails Terraform when a
playbook task fails.

## Why inventory is created in memory

The Ansible provider's `ansible_playbook` resource creates a basic temporary
inventory and does not automatically consume separate `ansible_host` and
`ansible_group` resources. The `cloud.terraform` state inventory plugin can
bridge those resources only after state is current. Its 4.0.0 release also
fails under this machine's Ansible Core 2.21 because it calls a removed
`get_bin_path` argument.

`terraform/ansible` therefore passes this shape directly from deployment state:

```json
{
  "vault-1": {"ansible_host": "192.0.2.1", "vault_role": "leader"},
  "vault-2": {"ansible_host": "192.0.2.2", "vault_role": "follower"},
  "vault-3": {"ansible_host": "192.0.2.3", "vault_role": "follower"}
}
```

The first play uses `add_host` to create the `vault` group in memory. The
second play performs convergence. This has no first-apply state race and does
not write a generated inventory containing secrets.

## Dependencies and SSH

```bash
make ansible-deps
make ansible-ssh
make ansible-check
```

Collections are pinned in `ansible/requirements.yml` and installed beneath the
ignored `.cache/ansible/collections` path. Controller temporary files also use
the ignored cache rather than the user's global Ansible directory.

Ansible does not use a personal SSH identity. `make ansible-ssh` creates
`.secrets/ansible/id_ed25519`, authorizes only its public half on the three
Terraform-managed nodes, records their ED25519 host keys, and verifies strict
host-key checking. `-F /dev/null` prevents a macOS-only `UseKeychain` setting in
the user's SSH config from affecting automation.

If a known host key changes, the command fails. Verify that the VM was
intentionally rebuilt before approving it with:

```bash
CONFIRM_ANSIBLE_HOST_KEY_CHANGE=yes make ansible-ssh
```

## Roles and order

`ansible/site.yml` runs:

1. `rhel_prepare` — validates RHEL/ARM64/SELinux, repairs DNS only when needed,
   performs activation-key RHSM registration only when firewalld is absent,
   and ensures firewalld is active.
2. `vault_install` — downloads the pinned archive, verifies SHA-256, creates
   the service account/directories, installs Vault, opens 8200/8201, and
   disables swap.
3. `tls` — preserves the local CA, creates IP-specific node certificates, and
   distributes them.
4. `vault_license` — installs the raw license with `root:vault 0640` and does
   not log its contents.
5. `vault_configure` — writes `vault.hcl`, peer host entries, and the hardened
   systemd unit.
6. `vault_bootstrap` — initializes only once, joins followers before unsealing,
   unseals restarted nodes, creates/reuses the platform token, and checks Raft.
7. `vault_validate` — checks service, TLS, seal/HA state, SELinux, swap,
   firewall, three voters, and license status.

## Reruns and Terraform state

The resource uses `replayable = false`, so an ordinary Terraform plan can be
clean. `make ansible-converge` explicitly replaces only the playbook resource
when an operational rerun is requested. Destroying/recreating that resource
does not destroy any VM or Vault data.

Changes under `ansible`, `templates`, or the platform-admin policy alter an
automation digest and naturally replace the resource on the next apply.

The provider stores stdout and stderr in `terraform/ansible/terraform.tfstate`.
Never put a secret in `extra_vars`; paths and topology only are passed there.
Tasks using RHSM credentials, licenses, unseal keys, or tokens must retain
`no_log: true`.

## Checks

```bash
make ansible-check       # syntax plus read-only ping proof
make ansible-plan        # Terraform preview
make ansible-converge    # run/re-run convergence
make ansible-validate    # require no orchestration drift
make state-secret-check  # scan local state without printing secrets
```

Full Ansible check mode is intentionally not advertised as a safe plan. Some
bootstrap API operations cannot provide meaningful check-mode predictions.
Terraform plan plus the syntax/ping proof is the non-mutating gate.
