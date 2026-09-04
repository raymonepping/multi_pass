# Reproducible Vault Enterprise lab on Multipass

## Objective

Build and verify a reproducible, local, three-node HashiCorp Vault Enterprise
lab on an Apple Silicon Mac. Multipass runs three RHEL 9.8 ARM64 virtual
machines, Terraform owns only VM lifecycle, external scripts perform host and
Vault bootstrap, and a separate Terraform root configures the Vault platform.

The implementation must be safe to publish. No Vault license, private key,
unseal key, root token, administrative token, secret value, Terraform state,
or generated credential may enter Git or Terraform state.

## Validated decisions

- Use Terraform `>= 1.11, < 2.0`.
- Pin `todoroff/multipass` to `1.7.1`. This is a community provider that drives
  the locally installed Multipass CLI; document that dependency explicitly.
- Pin `hashicorp/vault` to `5.11.0`. Provider 5.x requires Terraform 1.11 or
  newer and supports the selected Vault server release.
- Pin Vault Enterprise to `2.1.0+ent` by default and install the Linux ARM64
  release archive only after verifying it against HashiCorp's published
  SHA-256 checksums. This is the deterministic path for an unregistered RHEL
  image; do not rely on unavailable RHEL repositories.
- Commit `.terraform.lock.hcl` files. They lock provider artifacts and do not
  contain credentials. Never commit Terraform state or plans.
- A pre-apply plan must complete successfully; a post-apply plan must report
  no changes.
- Use Shamir seal with three key shares and threshold two by default.
- Use integrated Raft storage with all three nodes as voters.
- Use one locally generated CA, created outside Terraform, and a unique server
  certificate per node. Certificates must contain the node name, localhost,
  and the node's current IP SAN. TLS verification must remain enabled.
- Configure `disable_mlock = true` and disable swap, as recommended for Raft.
- Retain SELinux enforcing. Open only TCP 8200 and 8201 in firewalld. If
  firewalld is absent in the custom image, fail with an actionable message;
  do not weaken the requirement silently.
- Use the proven cloud-init semaphore workaround that skips Multipass's
  Ubuntu-only `pollinate` vendor package while retaining networking, SSH,
  growpart, resizefs, and user setup.

## Scope and ownership boundaries

### Layer 1: infrastructure Terraform

Directory: `terraform/infra`

Create `vault-1`, `vault-2`, and `vault-3` from a configurable local RHEL 9.8
ARM64 qcow2 image. Defaults are 2 CPUs, 4 GiB RAM, and 20 GiB disk per node.
Expose only non-sensitive node names and IP addresses. Terraform must not run
bootstrap provisioners, create TLS material, or process Vault credentials.

### Layer 2: external bootstrap

Directory: `scripts`, with generated sensitive files under `.secrets`

Provide idempotent scripts that:

1. Check host prerequisites, image existence/checksum, license input, VM
   cloud-init completion, architecture, OS, disk, SSH access, SELinux, and
   firewalld.
2. Download Vault Enterprise on the host, verify its checksum, and install the
   binary plus service account/directories on the VMs.
3. Generate the CA and node certificates outside Terraform.
4. copy the caller-supplied license to `/opt/vault/vault.hclic` as
   `root:vault` mode `0640`; never print its contents.
5. Configure Vault with a unique Raft `node_id`, separate data directory,
   routable API/cluster addresses, verified TLS, `license_path`, UI enabled,
   and `disable_mlock = true`.
6. Install and enable a hardened systemd service.
7. Initialize `vault-1` exactly once, saving JSON as
   `.secrets/vault-init.json` mode `0600`; unseal it with the threshold number
   of keys; join `vault-2` and `vault-3` to its Raft cluster before unsealing
   them; and verify three voters.
8. Create a narrowly documented initial platform-admin policy/token outside
   Terraform and save the token mode `0600` under `.secrets`.
9. Validate health, TLS, seal/HA state, license status, Raft peers, systemd,
   SELinux, swap, and firewall state without leaking secrets.

Scripts must use strict shell mode, quote variables, have useful errors, avoid
logging sensitive values, and be safe to rerun. They may only modify the three
named lab VMs and local generated lab files. They must never mutate unrelated
Multipass instances.

### Layer 3: Vault platform Terraform

Directory: `terraform/platform`

Authenticate only through environment variables or the generated local token
file wrapper. Never declare a token in Terraform configuration or variables.
Use data-driven maps to create example Enterprise namespaces and mounts:

- KV v2
- Transit
- PKI mount only (do not generate a CA/private key in Terraform state)

Resources must explicitly target their namespace. The example defaults should
be useful but replaceable through non-secret tfvars. Apply only after the
cluster is initialized, unsealed, licensed, and healthy. A second plan must be
clean.

## Repository interface

Provide these Make targets:

- `check`: local static/prerequisite checks
- `infra-plan`, `infra`, `infra-validate`
- `tls`, `install`, `license`, `configure`, `bootstrap`, `validate`
- `platform-plan`, `platform`, `platform-validate`
- `failover-help`: print the manual acceptance procedure only
- `destroy`: destroy only Terraform-managed `vault-1..3` VMs, retaining an
  interactive Terraform confirmation unless explicitly overridden by the user

Provide `.env.example` and `*.tfvars.example` files containing paths and safe
non-secret examples only. Accept the license as `VAULT_LICENSE_FILE`; it must
point outside the repository or to an ignored file. Default the image path to
`/Users/Shared/rhel-9.8-aarch64-kvm.qcow2` but keep it configurable.

## Gated execution

Execute in this order and stop at the first failed gate:

1. Static validation and host prerequisites.
2. Terraform init/validate/plan and infrastructure apply.
3. Validate all VMs and cloud-init.
4. Install/configure one node and check the service, then repeat for all nodes.
5. Generate/distribute TLS and license without exposing them.
6. Initialize the first node, join/unseal the followers, and validate Raft.
7. Record but do not automatically perform the manual failover test.
8. Initialize/validate/plan/apply the platform layer and require a clean second
   plan.

If a license file is unavailable or invalid, stop before initializing Vault
and explain exactly how to resume. Never substitute Vault Community edition.
If infrastructure apply requires a destructive replacement of an existing
managed VM, surface the Terraform plan and require normal confirmation.

## Acceptance criteria

- Three RHEL 9.8 ARM64 VMs exist with requested sizing and healthy cloud-init.
- Vault Enterprise `2.1.0+ent` is checksum-verified, installed, licensed, and
  managed by systemd on each node.
- TLS is valid with hostname/IP SANs and no insecure client flags.
- SELinux is enforcing, swap is disabled, and only Vault ports are opened by
  this project.
- The cluster has one leader, two standby nodes, and three Raft voters.
- Re-running bootstrap is safe and does not reinitialize or rotate secrets.
- Platform resources exist in the configured namespaces and a second plan is
  empty.
- `git status` contains no sensitive/generated material, state, or plan files.
- README documents prerequisites, execution, recovery/resume behavior,
  verification, manual failover, teardown, and security boundaries.

## Final report

Report what was created, exact versions, validation results, any gate not run
and why, paths to local sensitive artifacts without showing contents, and the
next safe command. Do not claim acceptance criteria that were not tested.
