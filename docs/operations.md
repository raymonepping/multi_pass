# Operations

## Resume points

Every script is designed to be rerun. If execution stops, fix the reported
gate and rerun its Make target. In particular:

- Missing license: export `VAULT_LICENSE_FILE` and resume with `make license`.
- Missing `firewalld`: export `RHSM_ORG` and `RHSM_ACTIVATION_KEY`, then run
  `make rhel-prepare`. Alternatively, replace/rebuild the source qcow2 with
  `firewalld` preinstalled. Do not proceed by disabling the firewall gate or
  mixing packages from a different distribution.
- RHSM reports `Name or service not known`: rerun `make rhel-prepare`. It
  distinguishes broken DNS from a broken Multipass NAT path and persists the
  configurable `RHEL_DNS_SERVERS` through NetworkManager when only DNS is
  affected.
- Expired/invalid license: replace the source file and rerun `make license
  configure`.
- Changed VM IP: rerun `make tls configure`; node certificates are regenerated
  only when the current IP SAN is absent.
- Sealed node after restart: use two keys from the ignored
  `.secrets/vault-init.json` with `vault operator unseal`, then run
  `make validate`. The scripts never auto-unseal on boot because this lab uses
  Shamir seal.
- Lost `.secrets/vault-init.json`: do not reinitialize or destroy the cluster.
  Restore the file from your secure backup.

## Manual failover acceptance test

This test is deliberately not automated because it changes live cluster state.

1. Run `make validate` and note the node whose `ha_mode` is `active`.
2. Stop Vault only on that node:

   ```sh
   multipass exec <active-node> -- sudo systemctl stop vault
   ```

3. Wait briefly, then inspect the two remaining nodes using `vault status` with
   `VAULT_ADDR` and `VAULT_CACERT`. Confirm exactly one has become active.
4. Start the original node:

   ```sh
   multipass exec <active-node> -- sudo systemctl start vault
   ```

5. Because Shamir seal is used, unseal the restarted node with any two distinct
   keys from `.secrets/vault-init.json`. Never paste keys into shell history on
   a shared machine.
6. Run `make validate` and confirm one active, two standby, and three voters.

## Teardown

`make destroy` invokes Terraform's normal interactive destroy confirmation and
targets only the three resources owned by `terraform/infra`. It does not delete
unrelated Multipass instances. Local `.secrets` and `.cache` artifacts are
retained so their deletion is a separate, explicit operator decision.

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
