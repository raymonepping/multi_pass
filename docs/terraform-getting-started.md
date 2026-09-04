# Terraform roots

The repository uses three local Terraform roots with separate state files.

| Root | Providers | Responsibility |
|---|---|---|
| `terraform/infra` | `todoroff/multipass`, `hashicorp/local` | VMs, rendered cloud-init, non-secret topology |
| `terraform/ansible` | `ansible/ansible` | Run and supervise Ansible convergence |
| `terraform/platform` | `hashicorp/vault` | Vault namespaces and mounts |

All provider versions are exact-pinned and each root's lockfile is committed.
State, plans, provider downloads, and generated cloud-init are ignored.

## Deployment root

```bash
make deployment-plan
make deployment
```

`terraform/infra` creates exactly `vault-1`, `vault-2`, and `vault-3`. It
renders cloud-init from `cloud-init/rhel.yaml.tftpl` using only the dedicated
public key. The private key is never read by Terraform.

Outputs are a non-secret handoff:

- `node_names`
- `node_ipv4`
- `ansible_nodes`
- `vault_api_addresses`

Existing instances ignore a change to the cloud-init source because cloud-init
is immutable after creation and replacing a running Vault node merely to add a
public key is unsafe. `scripts/ansible-ssh.sh` performs the scoped in-place
public-key migration instead. Newly created instances receive the rendered
file normally.

## Ansible orchestration root

```bash
make ansible-plan
make ansible-converge
make ansible-validate
```

`terraform/ansible` reads deployment outputs through a local
`terraform_remote_state` data source. Deployment state must therefore remain
strictly non-secret: state readers can access the entire snapshot, not only
declared outputs.

The root passes node JSON and ignored file paths to `ansible_playbook`; no
secret value is a Terraform input. The resource captures playbook output in
its own ignored state, so sensitive Ansible tasks use `no_log`.

## Vault platform root

```bash
make platform-plan
make platform
make platform-validate
```

`terraform/platform` reads the `vault-1` API address from deployment state.
`scripts/platform.sh` exports only `VAULT_CACERT` and the contents of the
ignored `.secrets/platform-token` for provider authentication. The token is
never declared as a Terraform variable.

The defaults create:

```text
engineering/
├── kv/       (KV v2)
└── transit/
operations/
└── pki/
```

The PKI resource creates a mount only; it does not generate CA private keys in
Terraform state.

## Why these cannot be one Terraform apply

Terraform provider configuration must be available before resources are
applied. The Vault platform token does not exist until Ansible initializes or
reconciles the cluster, so configuring and using the Vault provider in the
same apply would create an invalid dependency cycle and an unsafe secret-state
boundary.

`make lab` is the one-command interface and provides the explicit sequence:

```text
infra apply -> ansible apply -> platform apply
```

Each phase is independently resumable after a failure.

## Safe planning and teardown

Always inspect deployment changes before accepting a replacement:

```bash
make deployment-plan
```

The automation never auto-approves deployment Terraform. Platform and Ansible
apply use `-auto-approve` only after their prerequisite validation gates; they
cannot own or destroy Multipass VMs.

Before VM teardown, optionally unregister the RHEL systems through the separate
confirmed target:

```bash
CONFIRM_RHSM_UNREGISTER=yes make rhel-unregister
make destroy
```

`make destroy` retains Terraform's interactive confirmation and is scoped to
deployment resources. Local `.secrets` are deliberately retained for recovery.
