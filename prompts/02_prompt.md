# Resolve the RHEL package and firewalld prerequisite gate

## Context

The first deployment prompt successfully created the three Terraform-managed
RHEL 9.8 ARM64 guests, but execution correctly stopped during VM validation.
The supplied minimal qcow2 contains neither `firewalld` nor `nftables`, and
`dnf repolist --enabled` reports no repositories. Vault must not be installed
or initialized by bypassing this security gate.

Runtime diagnosis also established that the Multipass-provided resolver
`192.168.252.1` can fail while raw HTTPS connectivity still works. Treat this
as a DNS-specific prerequisite: test resolution before RHSM registration and,
only when raw connectivity succeeds, persist configurable fallback resolvers
through the guest's existing NetworkManager connection. Do not overwrite
`/etc/resolv.conf` directly.

RHEL protected package content requires the guest to be registered with an
appropriate Red Hat subscription or Satellite organization. Red Hat documents
activation-key registration as:

```text
subscription-manager register --activationkey=<key> --org=<organization>
```

Once repositories are enabled, `dnf install firewalld` is the supported package
installation path.

## Objective

Add an explicit, idempotent RHEL preparation stage between `make infra` and
`make infra-validate`. It may register and install packages only on the three
VMs already owned by the infrastructure Terraform state. It must not weaken
the firewall requirement, mix CentOS/UBI packages into RHEL, modify unrelated
Multipass guests, or put Red Hat credentials into Terraform, Git, logs, or
persistent project files.

## Inputs and secret handling

- Accept only activation-key registration through the caller's environment:
  `RHSM_ORG` and `RHSM_ACTIVATION_KEY`.
- Do not accept a Red Hat username/password in automation.
- Do not source `.env` automatically and never echo either value.
- When a guest is already registered, require no credentials.
- If registration is required, place the two values in a mode-`0600` temporary
  host file under an ignored/private directory, transfer it to a mode-`0600`
  temporary guest file, and delete both through traps.
- Invoke a static guest helper that reads the file without shell tracing. The
  `subscription-manager` process necessarily receives its documented options;
  acknowledge the brief guest process-table exposure in security docs.

## Required implementation

Create `make rhel-prepare` backed by strict shell scripts that:

1. Resolve the allowed VM names from `terraform/infra` state and confirm that
   `vault-1`, `vault-2`, and `vault-3` are running.
2. For each node, validate RHEL 9 and ARM64 before making changes.
3. Test resolution of `subscription.rhsm.redhat.com`. If resolution fails,
   confirm raw HTTPS connectivity, configure `RHEL_DNS_SERVERS` through
   NetworkManager, reactivate the connection, and require resolution to pass.
   Default to `1.1.1.1,1.0.0.1`, but make the value configurable.
4. If `firewalld` is already installed, enable/start it and continue without
   attempting registration.
5. Otherwise, check `subscription-manager identity`.
6. If unregistered and either activation-key input is absent, stop with an
   actionable message and make no registration attempt.
7. If inputs exist, register with Red Hat using the documented activation-key
   flow, suppressing credential values from output.
8. Require at least one enabled DNF repository, run `dnf install -y firewalld`,
   enable/start `firewalld`, and verify it is active.
9. Do not open Vault ports yet; the existing Vault installation stage remains
   responsible for TCP 8200/8201.

Also add a separately gated `make rhel-unregister` operation. It must require
`CONFIRM_RHSM_UNREGISTER=yes`, affect only the three Terraform-managed guests,
skip already unregistered guests, call the official `subscription-manager
unregister` command, and verify the identity is removed. Do not call it
automatically during ordinary validation or Terraform destroy.

## Integration updates

- Update the normal workflow to `infra -> rhel-prepare -> infra-validate`.
- Keep `infra-validate` read-only and retain its hard failure when `firewalld`
  is missing.
- Extend `.env.example` with empty RHSM variables, never realistic-looking
  credentials.
- Update README and operations documentation with registration prerequisites,
  rerun behavior, credential boundaries, optional unregister-before-destroy,
  and the fact that unregistered systems cannot receive protected updates.
- Add `rhel-prepare` and `rhel-unregister` to Make help/interface documentation.
- Preserve every secret/state ignore rule and both committed provider lockfiles.

## Execution gates

1. Run Bash syntax checks, ShellCheck, Terraform validation, formatting checks,
   and Git whitespace/secret-path checks.
2. Run `make rhel-prepare`.
3. If RHSM inputs are unavailable, stop cleanly with the exact required
   variables and do not attempt workarounds using another distribution's
   repositories.
4. If preparation succeeds, rerun `make infra-validate` and continue the
   original prompt from `make install`.

## Acceptance criteria

- The preparation stage is idempotent and scoped to the Terraform-owned nodes.
- Activation-key values are absent from Git, Terraform configuration/state,
  normal command output, and persistent local/guest files.
- All three guests have an active `firewalld` installed from enabled RHEL
  repositories.
- The existing security gate remains enforced.
- Optional unregistration is explicit, confirmed, scoped, and documented.
- No Vault installation or initialization occurs until this gate passes.
