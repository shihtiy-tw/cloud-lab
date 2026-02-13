.PHONY: help aws gcp azure oracle test lint security docs clean

# Default target
help: ## Show this help
	@echo "cloud-lab - Multi-Cloud Infrastructure"
	@echo ""
	@echo "Usage: make [target] [CLOUD=aws|gcp|azure|oracle] [SERVICE=path] [ENV=dev|staging|prod]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

# Cloud context switching
aws: ## Switch to AWS context
	@./scripts/cloud.switch.sh --cloud aws
	@echo "Switched to AWS context"

gcp: ## Switch to GCP context
	@./scripts/cloud.switch.sh --cloud gcp
	@echo "Switched to GCP context"

azure: ## Switch to Azure context
	@./scripts/cloud.switch.sh --cloud azure
	@echo "Switched to Azure context"

oracle: ## Switch to Oracle context
	@./scripts/cloud.switch.sh --cloud oracle
	@echo "Switched to Oracle context"

# Core operations
init: ## Initialize new service: make init CLOUD=aws CATEGORY=compute NAME=my-service
	@./scripts/cloud.init.sh --cloud $(CLOUD) --category $(CATEGORY) --name $(NAME)

provision: ## Provision infrastructure: make provision CLOUD=aws SERVICE=compute/ecs ENV=dev
	@./scripts/cloud.provision.sh --cloud $(CLOUD) --service $(SERVICE) --env $(ENV)

plan: ## Plan infrastructure: make plan CLOUD=aws SERVICE=compute/ecs ENV=dev
	@./scripts/cloud.provision.sh --cloud $(CLOUD) --service $(SERVICE) --env $(ENV) --plan-only

destroy: ## Destroy infrastructure: make destroy CLOUD=aws SERVICE=compute/ecs ENV=dev
	@./scripts/cloud.provision.sh --cloud $(CLOUD) --service $(SERVICE) --env $(ENV) --destroy

# Testing
test: ## Run tests: make test CLOUD=aws SERVICE=compute/ecs
	@./scripts/cloud.test.sh --cloud $(CLOUD) --service $(SERVICE)

test-all: ## Run all tests for a cloud: make test-all CLOUD=aws
	@./scripts/cloud.test.sh --cloud $(CLOUD) --all

# Quality and security
lint: ## Run linters on Terraform files
	@terraform fmt -check -recursive $(CLOUD)/
	@tflint --recursive $(CLOUD)/

security: ## Run security scans: make security CLOUD=aws SERVICE=compute/ecs
	@./scripts/cloud.security.sh --cloud $(CLOUD) --service $(SERVICE)

security-all: ## Run security scans for entire cloud: make security-all CLOUD=aws
	@./scripts/cloud.security.sh --cloud $(CLOUD) --all

# Documentation
docs: ## Generate documentation: make docs CLOUD=aws SERVICE=compute/ecs
	@./scripts/cloud.docs.sh --cloud $(CLOUD) --service $(SERVICE)

docs-all: ## Generate all documentation: make docs-all CLOUD=aws
	@./scripts/cloud.docs.sh --cloud $(CLOUD) --all

# Cost analysis
cost: ## Show cost analysis: make cost CLOUD=aws
	@./scripts/cloud.cost.sh --cloud $(CLOUD) --timeframe 30d

cost-estimate: ## Estimate costs from plan: make cost-estimate CLOUD=aws SERVICE=compute/ecs
	@./scripts/cloud.cost.sh --cloud $(CLOUD) --estimate --service $(SERVICE)

# Utilities
fmt: ## Format all Terraform files
	@terraform fmt -recursive .

validate: ## Validate Terraform files: make validate CLOUD=aws SERVICE=compute/ecs
	@cd $(CLOUD)/$(SERVICE)/infrastructure && terraform validate

clean: ## Clean Terraform cache and lock files
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@echo "Cleaned Terraform cache files"

# Status
status: ## Show current cloud context
	@./scripts/cloud.switch.sh --show
