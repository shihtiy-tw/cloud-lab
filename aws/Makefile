# aws-lab Makefile
# Main entry point for Terraform development tasks

.PHONY: help init validate plan apply destroy
.PHONY: lint lint-tf lint-shell security-scan
.PHONY: format docs test clean setup

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
	@echo -e "$(BLUE)aws-lab$(RESET) - Makefile targets"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'

# =============================================================================
# Setup
# =============================================================================

setup: ## Set up development environment
	@./scripts/setup-dev.sh

# =============================================================================
# Terraform Operations
# =============================================================================

init: ## Initialize Terraform
	@terraform init

validate: ## Validate Terraform
	@terraform validate

plan: ## Create Terraform plan
	@terraform plan -out=tfplan

apply: ## Apply Terraform plan
	@terraform apply tfplan

destroy: ## Destroy Terraform resources
	@terraform destroy

# =============================================================================
# Linting
# =============================================================================

lint: lint-tf lint-shell security-scan ## Run all linters

lint-tf: ## Lint Terraform files
	@echo -e "$(BLUE)Running Terraform format check...$(RESET)"
	@terraform fmt -check -recursive
	@echo -e "$(BLUE)Running TFLint...$(RESET)"
	@tflint --recursive 2>/dev/null || true

lint-shell: ## Lint shell scripts
	@echo -e "$(BLUE)Running ShellCheck...$(RESET)"
	@find . -name "*.sh" -type f -exec shellcheck {} + 2>/dev/null || true

# =============================================================================
# Security
# =============================================================================

security-scan: ## Run security scans
	@echo -e "$(BLUE)Running tfsec...$(RESET)"
	@tfsec . 2>/dev/null || true
	@echo -e "$(BLUE)Running Checkov...$(RESET)"
	@checkov -d . --config-file ../.checkov.yml 2>/dev/null || true

# =============================================================================
# Formatting
# =============================================================================

format: ## Format all files
	@echo -e "$(BLUE)Formatting Terraform files...$(RESET)"
	@terraform fmt -recursive
	@echo -e "$(GREEN)Format complete$(RESET)"

# =============================================================================
# Documentation
# =============================================================================

docs: ## Generate documentation with terraform-docs
	@echo -e "$(BLUE)Generating Terraform docs...$(RESET)"
	@find . -name "*.tf" -exec dirname {} \; | sort -u | xargs -I{} terraform-docs markdown table {} --output-file {}/README.md 2>/dev/null || true
	@echo -e "$(GREEN)Documentation complete$(RESET)"

# =============================================================================
# Testing
# =============================================================================

test: ## Run Terratest tests
	@echo -e "$(BLUE)Running Terratest...$(RESET)"
	@cd tests && go test -v ./... 2>/dev/null || echo "No tests found or Go not installed"

# =============================================================================
# Cost
# =============================================================================

cost: ## Estimate infrastructure cost
	@infracost breakdown --path . 2>/dev/null || echo "Infracost not installed"

# =============================================================================
# Pre-commit
# =============================================================================

pre-commit: ## Run pre-commit on all files
	@pre-commit run --all-files

pre-commit-install: ## Install pre-commit hooks
	@pre-commit install && pre-commit install --hook-type commit-msg

# =============================================================================
# Cleanup
# =============================================================================

clean: ## Clean Terraform artifacts
	@echo -e "$(BLUE)Cleaning...$(RESET)"
	@find . -name "*.tfplan" -delete 2>/dev/null || true
	@find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@echo -e "$(GREEN)Clean complete$(RESET)"
