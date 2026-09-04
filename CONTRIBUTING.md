# Contributing

## Getting started

1. Fork the repository and create a feature branch from `main`.
2. Make your changes, following the code style of the existing scripts, Terraform files, and Ansible roles.
3. Commit using clear, conventional commit messages.
4. Open a pull request against `main` with a description of what changed and why.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add new feature
fix: correct a bug
chore: update dependencies
docs: improve README
refactor: restructure without behaviour change
```

## Code style

**Shell scripts**
- Use `set -euo pipefail`, source `common.sh`, and follow the patterns already in `scripts/`.
- No secrets, tokens, or license values ever appear in source files, commit messages, or PR descriptions.

**Terraform**
- Files are formatted with `terraform fmt` — `make check` enforces this.
- New resources belong in `terraform/platform/`; new variables get a `validation` block.

**Ansible**
- Use fully-qualified collection names (`ansible.builtin.*`, `community.crypto.*`, `ansible.posix.*`).
- Any task that registers, reads, or passes secret material must have `no_log: true`.
- Tasks that produce local files (init output, certs, tokens) use `delegate_to: localhost`.
- New roles follow the existing structure: `tasks/main.yml`, `handlers/main.yml`, `templates/` as needed.
- Keep `group_vars/vault.yml` as the single source of truth for version numbers and paths —
  never hardcode them inside a role.

## Required Ansible collections

Install once before working on or running Ansible roles:

```sh
ansible-galaxy collection install community.crypto ansible.posix
```

## Secrets & security

- Licenses live in `.secrets/keys/` and are covered by `.gitignore`. Never commit them.
- `make check` runs `gitleaks` via the pre-commit hook and blocks sensitive filenames from being staged.
- Report security vulnerabilities privately rather than opening a public issue.

## Testing your changes

Run the full validation chain before opening a PR:

```bash
make check
make infra-validate
make validate
make platform-validate
```

For Ansible changes, also verify connectivity and a dry-run:

```bash
ansible vault -m ping --private-key ~/.ssh/id_ed25519 -u ubuntu
ansible-playbook ansible/site.yml --check --diff
```

All checks must pass with no errors.

## Pull request review

All pull requests require at least one approval before merging to `main`.
