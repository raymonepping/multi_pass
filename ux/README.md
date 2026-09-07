# Multipass control plane

Local Nuxt control surface for the repository's `Terraform → RHEL → Ansible → Vault` lifecycle.

Use a Nuxt-supported Node release: Node 22.19+, 24.11+, or 26+. Node 24 LTS is
the recommended local choice.

## Run

```bash
npm install
npm run dev
```

Open <http://127.0.0.1:3000>. The server binds to loopback through the package script. Run it from this `ux/` directory so the default repository root resolves correctly. Override the root only with an operator-controlled environment variable:

```bash
MULTIPASS_CONTROL_REPOSITORY_ROOT=/absolute/path/to/multi_pass npm run dev
```

For the production build, use `npm run build && npm start`; the launcher also
defaults to `127.0.0.1`.

## What the statuses prove

- **Terraform** reads only the `node_names` and `node_ipv4` deployment outputs. State unavailable means unknown; absence from readable state means unmanaged.
- **RHEL** runs fixed, read-only guest checks for release, architecture, SELinux, swap, firewalld, and failed services.
- **Ansible** compares the applied orchestration digest and node set with a fresh digest of the repository's declared automation files.
- **Vault** combines fixed node health checks with the existing `scripts/validate.sh` cluster contract. The cluster contract verifies HA roles, Raft voters, and license state without returning secrets to the browser.

No full Terraform state, Ansible output, environment data, root tokens, unseal keys, license contents, private keys, or arbitrary command surface is exposed by the API.

## Verify

```bash
npm run typecheck
npm run lint
npm test
npm run build
```
