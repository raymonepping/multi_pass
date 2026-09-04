# Vault — Getting Started

This guide assumes the cluster is already up (`make validate` passes) and
covers everyday interaction: setting up your shell, navigating the cluster,
reading and writing secrets, and working with the secret engines that are
deployed by default.

---

## 1. Shell setup

Every Vault CLI command needs three environment variables. Source them once per
terminal session.

```bash
# Active node IP (vault-1 is the leader)
export VAULT_ADDR="https://$(cd /path/to/multi_pass && \
  terraform -chdir=terraform/infra output -json node_ipv4 | jq -r '.["vault-1"]'):8200"

# CA certificate that signed the cluster's TLS certificates
export VAULT_CACERT="/path/to/multi_pass/.secrets/tls/ca.crt"

# Root token — use a scoped token for day-to-day work (see section 2)
export VAULT_TOKEN=$(jq -r '.root_token' /path/to/multi_pass/.secrets/vault-init.json)
```

Replace `/path/to/multi_pass` with the actual repository path, or add a
helper to your shell profile:

```bash
# ~/.zshrc or ~/.bashrc
vault_lab() {
  local repo="/path/to/multi_pass"
  export VAULT_ADDR="https://$(terraform -chdir="${repo}/terraform/infra" \
    output -json node_ipv4 | jq -r '.["vault-1"]'):8200"
  export VAULT_CACERT="${repo}/.secrets/tls/ca.crt"
  export VAULT_TOKEN=$(jq -r '.root_token' "${repo}/.secrets/vault-init.json")
  echo "Vault environment set → ${VAULT_ADDR}"
}
```

Then just run `vault_lab` to load the env for a session.

---

## 2. Verify connectivity and cluster health

```bash
vault status
```

Expected output shows `Sealed: false`, `HA Mode: active`, and
`Storage Type: raft`. The standby nodes show `HA Mode: standby` or
`performance_standby`.

Check the Raft peer list:

```bash
vault operator raft list-peers
```

Three voters, one leader — the cluster is healthy.

---

## 3. Tokens

### Root token (break-glass only)

The root token is in `.secrets/vault-init.json` and has unlimited
capabilities. Use it only for initial setup or recovery. For all other work,
use a scoped token.

```bash
# Inspect the current token
vault token lookup
```

### Platform token (Terraform operations)

The platform token is in `.secrets/platform-token`. It is scoped to the
`lab-platform-admin` policy and is used by `make platform` and
`make platform-validate`. Its TTL renews automatically on use.

```bash
vault token lookup $(cat .secrets/platform-token)
```

### Create a short-lived interactive token

```bash
vault token create \
  -policy=lab-platform-admin \
  -ttl=4h \
  -display-name="my-session"
```

Export the returned token value and use it for the session:

```bash
export VAULT_TOKEN=<token-from-above>
```

Revoke it when done:

```bash
vault token revoke <token>
```

---

## 4. Namespaces

Vault Enterprise namespaces are isolated tenants within the same cluster.
This cluster has two:

| Namespace | Purpose |
|---|---|
| `engineering` | KV v2 store and Transit encryption |
| `operations` | PKI certificate authority |

Switch namespace via environment variable or the `-namespace` flag:

```bash
# Environment variable (persists for the session)
export VAULT_NAMESPACE=engineering

# Per-command flag
vault secrets list -namespace=engineering
```

List all namespaces from the root:

```bash
vault namespace list
```

---

## 5. KV v2 — reading and writing secrets

The KV v2 engine is mounted at `kv/` inside the `engineering` namespace.

```bash
export VAULT_NAMESPACE=engineering
```

### Write a secret

```bash
vault kv put kv/myapp/config \
  db_host="postgres.internal" \
  db_port="5432" \
  api_key="supersecret"
```

### Read a secret

```bash
vault kv get kv/myapp/config
```

Read a single field:

```bash
vault kv get -field=db_host kv/myapp/config
```

### Update — add or change a key

```bash
vault kv patch kv/myapp/config db_port="5433"
```

### List secrets at a path

```bash
vault kv list kv/
vault kv list kv/myapp/
```

### Read a previous version

```bash
# Show version history
vault kv metadata get kv/myapp/config

# Read version 1
vault kv get -version=1 kv/myapp/config
```

### Delete and recover

```bash
# Soft delete (recoverable)
vault kv delete kv/myapp/config

# Restore it
vault kv undelete -versions=2 kv/myapp/config

# Permanent destroy of a specific version
vault kv destroy -versions=1 kv/myapp/config
```

---

## 6. Transit — encryption as a service

The Transit engine is mounted at `transit/` inside the `engineering` namespace.
It never stores the plaintext — it only performs crypto operations.

```bash
export VAULT_NAMESPACE=engineering
```

### Create an encryption key

```bash
vault write -f transit/keys/myapp-key
```

### Encrypt data

The plaintext must be base64-encoded:

```bash
vault write transit/encrypt/myapp-key \
  plaintext=$(echo -n "hello world" | base64)
```

Copy the `ciphertext` value (starts with `vault:v1:`).

### Decrypt data

```bash
vault write transit/decrypt/myapp-key \
  ciphertext="vault:v1:<value-from-above>"
```

Decode the returned `plaintext`:

```bash
echo "<base64-plaintext>" | base64 -d
```

### Rotate the key

```bash
vault write -f transit/keys/myapp-key/rotate
```

Old ciphertext remains decryptable. Re-encrypt to use the new key version:

```bash
vault write transit/rewrap/myapp-key \
  ciphertext="vault:v1:<old-ciphertext>"
```

---

## 7. PKI — issuing certificates

The PKI engine is mounted at `pki/` inside the `operations` namespace.

```bash
export VAULT_NAMESPACE=operations
```

### Configure a root CA (first time only)

```bash
vault write pki/root/generate/internal \
  common_name="lab-root-ca" \
  ttl=87600h
```

### Configure URLs

```bash
vault write pki/config/urls \
  issuing_certificates="${VAULT_ADDR}/v1/pki/ca" \
  crl_distribution_points="${VAULT_ADDR}/v1/pki/crl"
```

### Create a role

```bash
vault write pki/roles/lab-server \
  allowed_domains="lab.internal" \
  allow_subdomains=true \
  max_ttl=720h
```

### Issue a certificate

```bash
vault write pki/issue/lab-server \
  common_name="myservice.lab.internal" \
  ttl=24h
```

The response contains `certificate`, `private_key`, and `ca_chain`.

---

## 8. Secret engines — listing and enabling

List all mounted engines in a namespace:

```bash
vault secrets list
vault secrets list -namespace=engineering
vault secrets list -namespace=operations
```

Enable a new engine (example: a second KV store for operations):

```bash
vault secrets enable \
  -namespace=operations \
  -path=config \
  -description="Operations config store" \
  kv-v2
```

> **Note:** secret engines added outside Terraform will not be tracked in
> state. Add them to `terraform/platform/variables.tf` under `mounts` and run
> `make platform` to bring them under Terraform management.

Disable an engine (destructive — all data at that path is deleted):

```bash
vault secrets disable -namespace=operations config/
```

---

## 9. Policies

List policies:

```bash
vault policy list
```

Read a policy:

```bash
vault policy read lab-platform-admin
```

Write a new policy from a local file:

```bash
cat > /tmp/my-policy.hcl <<'EOF'
path "engineering/kv/data/myapp/*" {
  capabilities = ["read"]
}
EOF

vault policy write myapp-read /tmp/my-policy.hcl
```

---

## 10. Audit log

Enable a file audit device (useful for debugging):

```bash
vault audit enable file file_path=/tmp/vault-audit.log
```

Tail it:

```bash
multipass exec vault-1 -- sudo tail -f /tmp/vault-audit.log | jq .
```

Disable when done:

```bash
vault audit disable file/
```

---

## 11. Unseal after a restart

This cluster uses Shamir seal. After a node restarts it is sealed and must be
manually unsealed with two of the three keys from `.secrets/vault-init.json`.

```bash
# Extract key 0 and key 1 (never store these in shell history on a shared machine)
KEY0=$(jq -r '.unseal_keys_b64[0]' .secrets/vault-init.json)
KEY1=$(jq -r '.unseal_keys_b64[1]' .secrets/vault-init.json)

VAULT_ADDR="https://<node-ip>:8200" vault operator unseal "${KEY0}"
VAULT_ADDR="https://<node-ip>:8200" vault operator unseal "${KEY1}"
```

Confirm the node is unsealed:

```bash
VAULT_ADDR="https://<node-ip>:8200" vault status
```

Then run `make validate` to confirm the full cluster is healthy.

---

## Quick reference

| Task | Command |
|---|---|
| Cluster status | `vault status` |
| List namespaces | `vault namespace list` |
| List secret engines | `vault secrets list` |
| Write a KV secret | `vault kv put kv/<path> key=value` |
| Read a KV secret | `vault kv get kv/<path>` |
| List KV secrets | `vault kv list kv/` |
| Encrypt with Transit | `vault write transit/encrypt/<key> plaintext=$(echo -n "x" \| base64)` |
| Decrypt with Transit | `vault write transit/decrypt/<key> ciphertext="vault:v1:..."` |
| Issue a certificate | `vault write pki/issue/<role> common_name=<cn>` |
| List policies | `vault policy list` |
| Create a token | `vault token create -policy=<name> -ttl=4h` |
| Revoke a token | `vault token revoke <token>` |
| Raft peer list | `vault operator raft list-peers` |
| Full health check | `make validate` |
