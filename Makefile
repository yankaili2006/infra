ENV := $(shell cat .last_used_env || echo "not-set")
ENV_FILE := $(PWD)/.env.${ENV}

-include ${ENV_FILE}

AWS_BUCKET_PREFIX ?= $(PREFIX)$(AWS_ACCOUNT_ID)-

.PHONY: provider-login
provider-login:
	$(MAKE) -C iac/provider-$(PROVIDER) provider-login

.PHONY: init
init:
	./scripts/confirm.sh $(TERRAFORM_ENVIRONMENT)
	$(MAKE) -C iac/provider-gcp init

# Setup production environment variables, this is used only for E2B.dev production
# Uses Infisical CLI to read secrets from Infisical Vault
# To update them, use the Infisical UI directly
# On a first use, you need to run `infisical login` and `infisical init`
.PHONY: download-prod-env
download-prod-env:
	@  ./scripts/download-prod-env.sh ${ENV}

.PHONY: plan
plan:
	$(MAKE) -C iac/provider-gcp plan

# Deploy all jobs in Nomad
.PHONY: plan-only-jobs
plan-only-jobs:
	$(MAKE) -C iac/provider-gcp plan-only-jobs

# Deploy a specific job name in Nomad
# When job name is specified, all '-' are replaced with '_' in the job name
.PHONY: plan-only-jobs/%
plan-only-jobs/%:
	$(MAKE) -C iac/provider-gcp plan-only-jobs/$(subst -,_,$(notdir $@))

.PHONY: plan-without-jobs
plan-without-jobs:
	$(MAKE) -C iac/provider-gcp plan-without-jobs

.PHONY: apply
apply:
	./scripts/confirm.sh $(TERRAFORM_ENVIRONMENT)
	$(MAKE) -C iac/provider-gcp apply

# Shortcut to importing resources into Terraform state (e.g. after creating resources manually or switching between different branches for the same environment)
.PHONY: import
import:
	./scripts/confirm.sh $(TERRAFORM_ENVIRONMENT)
	$(MAKE) -C iac/provider-gcp import

.PHONY: version
version:
	./scripts/increment-version.sh

.PHONY: build
build/%:
	$(MAKE) -C packages/$(notdir $@) build

.PHONY: build-and-upload
build-and-upload:build-and-upload/api
build-and-upload:build-and-upload/client-proxy
build-and-upload:build-and-upload/docker-reverse-proxy
build-and-upload:build-and-upload/clean-nfs-cache
build-and-upload:build-and-upload/orchestrator
build-and-upload:build-and-upload/template-manager
build-and-upload:build-and-upload/envd
build-and-upload:build-and-upload/clickhouse-migrator
build-and-upload/clean-nfs-cache:
	./scripts/confirm.sh $(TERRAFORM_ENVIRONMENT)
	GCP_PROJECT_ID=$(GCP_PROJECT_ID) $(MAKE) -C packages/orchestrator build-and-upload/clean-nfs-cache
build-and-upload/template-manager:
	./scripts/confirm.sh $(TERRAFORM_ENVIRONMENT)
	GCP_PROJECT_ID=$(GCP_PROJECT_ID) $(MAKE) -C packages/orchestrator build-and-upload/template-manager
build-and-upload/orchestrator:
	./scripts/confirm.sh $(TERRAFORM_ENVIRONMENT)
	GCP_PROJECT_ID=$(GCP_PROJECT_ID) $(MAKE) -C packages/orchestrator build-and-upload/orchestrator
build-and-upload/api:
	./scripts/confirm.sh $(TERRAFORM_ENVIRONMENT)
	GCP_PROJECT_ID=$(GCP_PROJECT_ID) $(MAKE) -C packages/api build-and-upload
	GCP_PROJECT_ID=$(GCP_PROJECT_ID) $(MAKE) -C packages/db build-and-upload
build-and-upload/clickhouse-migrator:
	./scripts/confirm.sh $(TERRAFORM_ENVIRONMENT)
	GCP_PROJECT_ID=$(GCP_PROJECT_ID) $(MAKE) -C packages/clickhouse build-and-upload
build-and-upload/%:
	./scripts/confirm.sh $(TERRAFORM_ENVIRONMENT)
	GCP_PROJECT_ID=$(GCP_PROJECT_ID) $(MAKE) -C packages/$(notdir $@) build-and-upload

.PHONY: copy-public-builds
copy-public-builds:
ifeq ($(PROVIDER),aws)
	mkdir -p ./.kernels
	mkdir -p ./.firecrackers
	gsutil -m cp -r gs://e2b-prod-public-builds/kernels/* ./.kernels/
	gsutil -m cp -r gs://e2b-prod-public-builds/firecrackers/* ./.firecrackers/
	aws s3 cp ./.kernels/ s3://${AWS_BUCKET_PREFIX}fc-kernels/ --recursive --profile ${AWS_PROFILE}
	aws s3 cp ./.firecrackers/ s3://${AWS_BUCKET_PREFIX}fc-versions/ --recursive --profile ${AWS_PROFILE}
	rm -rf ./.kernels
	rm -rf ./.firecrackers
else
	gsutil cp -r gs://e2b-prod-public-builds/kernels/* gs://$(GCP_PROJECT_ID)-fc-kernels/
	gsutil cp -r gs://e2b-prod-public-builds/firecrackers/* gs://$(GCP_PROJECT_ID)-fc-versions/
endif

.PHONY: download-public-kernels
download-public-kernels:
	mkdir -p ./packages/fc-kernels
	gsutil cp -r gs://e2b-prod-public-builds/kernels/* ./packages/fc-kernels/

.PHONY: generate
generate: generate/api generate/orchestrator generate/client-proxy generate/envd generate/db generate/shared generate-tests generate-mocks
generate/%:
	@echo "Generating code for *$(notdir $@)*"
	$(MAKE) -C packages/$(notdir $@) generate
	@printf "\n\n"

.PHONY: generate-tests
generate-tests: generate-tests/integration
generate-tests/%:
		@echo "Generating code for *$(notdir $@)*"
		$(MAKE) -C tests/$(notdir $@) generate
		@printf "\n\n"

.PHONY: migrate
migrate:
	$(MAKE) -C packages/db migrate

.PHONY: set-env
set-env:
	@ touch .last_used_env
	@ echo $(ENV) > .last_used_env
	@ . ${ENV_FILE}

.PHONY: switch-env
switch-env:
	@ printf "Switching from `tput setaf 1``tput bold`$(shell cat .last_used_env)`tput sgr0` to `tput setaf 2``tput bold`$(ENV)`tput sgr0`\n\n"
	$(MAKE) set-env ENV=$(ENV)
	make -C iac/provider-gcp switch

.PHONY: setup-ssh
setup-ssh:
	@ printf "Setting up SSH for env: `tput setaf 2``tput bold`$(ENV)`tput sgr0`\n"
	@ gcloud compute config-ssh --remove
	@ gcloud compute config-ssh --project $(GCP_PROJECT_ID) --quiet
	@ printf "SSH setup complete\n"

.PHONY: test
test:
	go work edit -json \
		| jq -r '.Use[] | select (.DiskPath | contains("packages")) | .DiskPath' \
		| xargs -I{} $(MAKE) -C {} test

.PHONY: test-integration
test-integration:
	$(MAKE) -C tests/integration test

.PHONY: connect-orchestrator
connect-orchestrator:
	$(MAKE) -C tests/integration connect-orchestrator

.PHONY: fmt
fmt:
	@./scripts/golangci-lint-install.sh "2.4.0"
	golangci-lint fmt
	terraform fmt -recursive

.PHONY: lint
lint:
	@./scripts/golangci-lint-install.sh "2.4.0"
	go work edit -json | jq -r '.Use[].DiskPath' | xargs -P 10 -I{} golangci-lint run {}/... --fix

.PHONY: generate-mocks
generate-mocks:
	go run github.com/vektra/mockery/v3@v3.5.0

.PHONY: tidy
tidy:
	scripts/golang-dependencies-integrity.sh

.PHONY: local-infra
local-infra:
	docker compose --file ./packages/local-dev/docker-compose.yaml up --abort-on-container-failure

# ========================================
# Local Deployment Targets
# ========================================
# These targets are for deploying E2B locally without cloud dependencies
# See local-deploy/README.md for详细文档

.PHONY: local-deploy-init
local-deploy-init:
	@echo "Initializing E2B local deployment..."
	bash local-deploy/scripts/00-init-all.sh

.PHONY: local-deploy-start
local-deploy-start:
	@echo "Starting all E2B services..."
	bash local-deploy/scripts/start-all.sh

.PHONY: local-deploy-stop
local-deploy-stop:
	@echo "Stopping all E2B services..."
	bash local-deploy/scripts/stop-all.sh

.PHONY: local-deploy-verify
local-deploy-verify:
	@echo "Verifying E2B deployment..."
	bash local-deploy/scripts/verify-deployment.sh

.PHONY: local-deploy-cleanup
local-deploy-cleanup:
	@echo "Cleaning up E2B temporary data..."
	bash local-deploy/scripts/cleanup.sh

.PHONY: local-deploy-logs
local-deploy-logs:
	@echo "Showing E2B logs..."
	@tail -f /tmp/e2b-logs/*.log

.PHONY: local-deploy-status
local-deploy-status:
	@echo "=== Nomad Jobs ==="
	@nomad job status || echo "Nomad not running"
	@echo ""
	@echo "=== Consul Services ==="
	@consul catalog services || echo "Consul not running"
	@echo ""
	@echo "=== Docker Services ==="
	@docker compose -f ./packages/local-dev/docker-compose.yaml ps

.PHONY: local-deploy-help
local-deploy-help:
	@echo "E2B Local Deployment Commands:"
	@echo ""
	@echo "  make local-deploy-init     - Initialize local deployment (first time setup)"
	@echo "  make local-deploy-start    - Start all services"
	@echo "  make local-deploy-stop     - Stop all services"
	@echo "  make local-deploy-verify   - Verify deployment status"
	@echo "  make local-deploy-status   - Show current service status"
	@echo "  make local-deploy-logs     - Tail all logs"
	@echo "  make local-deploy-cleanup  - Clean up temporary data"
	@echo ""
	@echo "For detailed documentation, see local-deploy/README.md"
