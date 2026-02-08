# Cloud Lab - Multi-Cloud Infrastructure Makefile
# Main entry point for development tasks across all cloud providers

.PHONY: help init plan apply destroy test clean lint docs
.PHONY: aws-init aws-plan aws-apply aws-destroy
.PHONY: gcp-init gcp-plan gcp-apply gcp-destroy
.PHONY: azure-init azure-plan azure-apply azure-destroy
.PHONY: oracle-init oracle-plan oracle-apply oracle-destroy

# Colors
GREEN=\033[0;32m
BLUE=\033[0;34m
RESET=\033[0m

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

.DEFAULT_GOAL := help

# =============================================================================
# Help
# =============================================================================

help: ## Show this help
	@echo -e "$(BLUE)cloud-lab$(RESET) - Multi-Cloud Infrastructure"
	@echo ""
	@echo "Usage: make [target] [CLOUD=aws|gcp|azure|oracle] [SERVICE=...]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'

# =============================================================================
# Global Operations
# =============================================================================

lint: ## Run linters (Terraform, Shell, Security)
	@echo -e "$(BLUE)Running Terraform format check...$(RESET)"
	@terraform fmt -check -recursive
	@echo -e "$(BLUE)Running TFLint...$(RESET)"
	@tflint --recursive --config .tflint.hcl
	@echo -e "$(BLUE)Running ShellCheck...$(RESET)"
	@find . -name "*.sh" -not -path "*/.git/*" -type f -exec shellcheck {} +
	@echo -e "$(BLUE)Running tfsec...$(RESET)"
	@tfsec . 
	@echo -e "$(BLUE)Running Checkov...$(RESET)"
	@checkov -d . --config-file .checkov.yml

format: ## Format all Terraform files
	@echo -e "$(BLUE)Formatting Terraform files...$(RESET)"
	@terraform fmt -recursive

docs: ## Generate documentation
	@echo -e "$(BLUE)Generating Terraform docs...$(RESET)"
	@find . -name "*.tf" -not -path "*/.git/*" -not -path "*/.terraform/*" -exec dirname {} \; | sort -u | xargs -I{} terraform-docs markdown table {} --output-file {}/README.md

test: ## Run all tests
	@echo -e "$(BLUE)Running Terratest...$(RESET)"
	@cd tests && go test -v ./...

clean: ## Clean up Terraform artifacts
	@echo -e "$(BLUE)Cleaning...$(RESET)"
	@find . -name "*.tfplan" -delete
	@find . -name ".terraform" -type d -exec rm -rf {} +
	@find . -name ".terraform.lock.hcl" -delete

# =============================================================================
# Cloud Specific Shortcuts
# =============================================================================

aws-init: ## Initialize AWS Terraform
	@$(MAKE) -C aws init

aws-plan: ## Plan AWS Terraform (requires path via arguments or runs in aws root)
	@$(MAKE) -C aws plan

aws-test: ## Run AWS tests
	@$(MAKE) -C aws test

# Add similar targets for other clouds as they become active
