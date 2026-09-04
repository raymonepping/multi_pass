SHELL := /bin/bash

.PHONY: check state-secret-check ansible-deps ansible-ssh-prepare ansible-ssh ansible-inventory ansible-check \
	infra-plan infra deployment-plan deployment rhel-prepare rhel-unregister infra-validate \
	ansible-plan ansible-converge ansible-validate tls install license configure bootstrap \
	validate platform-plan platform platform-validate lab failover-help destroy

check:
	./scripts/check.sh

state-secret-check:
	./scripts/check-state-secrets.sh

ansible-deps:
	./scripts/ansible-deps.sh

ansible-ssh-prepare:
	./scripts/ansible-ssh.sh prepare

ansible-ssh:
	./scripts/ansible-ssh.sh all

ansible-inventory: ansible-deps
	./scripts/ansible-inventory.sh

ansible-check: ansible-deps
	./scripts/ansible-check.sh

infra-plan: ansible-ssh-prepare check
	terraform -chdir=terraform/infra init
	terraform -chdir=terraform/infra validate
	terraform -chdir=terraform/infra plan

infra: ansible-ssh-prepare check
	terraform -chdir=terraform/infra init
	terraform -chdir=terraform/infra validate
	terraform -chdir=terraform/infra apply

deployment-plan: infra-plan

deployment: infra

rhel-prepare:
	./scripts/rhel-prepare.sh

rhel-unregister:
	./scripts/rhel-unregister.sh

infra-validate:
	./scripts/infra-validate.sh

ansible-plan: ansible-deps
	./scripts/ansible-run.sh plan

ansible-converge: ansible-deps ansible-check
	./scripts/ansible-run.sh apply

ansible-validate:
	./scripts/ansible-run.sh validate

tls: infra-validate
	./scripts/tls.sh

install: infra-validate
	./scripts/install.sh

license: infra-validate
	./scripts/license.sh

configure: infra-validate
	./scripts/configure.sh

bootstrap:
	./scripts/bootstrap.sh

validate:
	./scripts/validate.sh

platform-plan: validate
	./scripts/platform.sh plan

platform: validate
	./scripts/platform.sh apply

platform-validate: validate
	./scripts/platform.sh validate

lab:
	./scripts/lab.sh

failover-help:
	@sed -n '/^## Manual failover acceptance test/,$$p' docs/operations.md

destroy:
	@echo "Terraform will propose destruction only for the vault-1..3 resources in terraform/infra."
	terraform -chdir=terraform/infra destroy
