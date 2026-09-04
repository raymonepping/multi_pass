# Release checklist

## Before tagging

- [ ] All changes merged to `main` and CI checks green
- [ ] `make check` passes locally
- [ ] Ansible connectivity verified: `make ansible-check`
- [ ] Ansible orchestration plan clean: `make ansible-validate`
- [ ] CHANGELOG.md updated — move items from `[Unreleased]` to a new version
      section following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
      format (e.g. `## [1.2.0] - 2026-09-04`)
- [ ] Version bump decided following [Semantic Versioning](https://semver.org/):
  - `patch` — bug fixes and resume-point corrections
  - `minor` — new Make targets, new Terraform resources, new script features
  - `major` — breaking changes to the runbook, incompatible script interface
      changes, or major dependency upgrades

## Tag and release

```sh
# Create and push an annotated tag — the release workflow triggers on v* tags
git tag -a v<version> -m "Release v<version>"
git push origin v<version>
```

- [ ] Tag pushed to `origin`
- [ ] GitHub release created with correct tag and notes

## After release

- [ ] Confirm the GitHub release page shows the correct tag and notes
- [ ] Open a fresh `[Unreleased]` section in CHANGELOG.md and commit to `main`:

  ```markdown
  ## [Unreleased]

  ### Added
  ### Changed
  ### Fixed
  ```

- [ ] Announce if applicable
