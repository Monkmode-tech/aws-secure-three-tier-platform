ENV_DIR ?= environments/dev
TF      := terraform -chdir=$(ENV_DIR)

.PHONY: help fmt validate lint scan init plan apply destroy smoke security load watch

help: ## Show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

fmt: ## Format all Terraform
	terraform fmt -recursive

validate: ## Validate bootstrap and the dev environment (no backend)
	terraform -chdir=bootstrap init -backend=false -input=false >/dev/null && terraform -chdir=bootstrap validate
	$(TF) init -backend=false -input=false >/dev/null && $(TF) validate

lint: ## tflint across all modules
	tflint --init && tflint --recursive --config "$(CURDIR)/.tflint.hcl"

scan: ## checkov IaC security scan
	checkov --config-file .checkov.yaml -d .

init: ## Init the dev environment with backend.hcl
	$(TF) init -backend-config=backend.hcl

plan: ## Plan the dev environment
	$(TF) plan -out=tfplan

apply: ## Apply the saved plan
	$(TF) apply tfplan

destroy: ## Destroy the dev environment (do this after every session)
	$(TF) destroy

smoke: ## Check the site answers
	./scripts/smoke-test.sh

security: ## Validate live security controls, write evidence report
	./scripts/validate-security.sh

load: ## Run the k6 ramp test against app_url
	TARGET_URL=$$($(TF) output -raw app_url) k6 run --summary-export docs/evidence/k6-summary.json scripts/load-test.js

watch: ## Record scaling activity to docs/evidence/
	./scripts/watch-scaling.sh
