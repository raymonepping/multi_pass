SHELL := /bin/bash

.PHONY: check infra-plan infra rhel-prepare rhel-unregister infra-validate tls install license \
	configure bootstrap validate platform-plan platform platform-validate failover-help destroy

check:
	./scripts/check.sh

infra-plan: check
	terraform -chdir=terraform/infra init
	terraform -chdir=terraform/infra validate
	terraform -chdir=terraform/infra plan

infra: check
	terraform -chdir=terraform/infra init
	terraform -chdir=terraform/infra validate
	terraform -chdir=terraform/infra apply

rhel-prepare:
	./scripts/rhel-prepare.sh

rhel-unregister:
	./scripts/rhel-unregister.sh

infra-validate:
	./scripts/infra-validate.sh

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

failover-help:
	@sed -n '/^## Manual failover acceptance test/,$$p' docs/operations.md

destroy:
	@echo "Terraform will propose destruction only for the vault-1..3 resources in terraform/infra."
	terraform -chdir=terraform/infra destroy
