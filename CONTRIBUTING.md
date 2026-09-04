# Contributing

## Getting started

1. Fork the repository and create a feature branch from `main`.
2. Make your changes, following the code style of the existing scripts and Terraform files.
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

- Shell scripts use `set -euo pipefail`, source `common.sh`, and follow the patterns already in `scripts/`.
- Terraform files are formatted with `terraform fmt` — `make check` enforces this.
- No secrets, tokens, or license values ever appear in source files, commit messages, or PR descriptions.

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

All four must pass with no errors.

## Pull request review

All pull requests require at least one approval before merging to `main`.
