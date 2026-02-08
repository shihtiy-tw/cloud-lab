---
id: spec-012  
title: CI/CD & Automation
type: enhancement
priority: high
status: planned
assignable: true
estimated_hours: 14
tags: [cicd, terraform, automation]
---

# CI/CD & Automation for aws-lab

## Overview
Create CI/CD pipelines for Terraform infrastructure.

## Tasks

### GitHub Actions Workflows (7 tasks)
- [ ] Create Terraform validate workflow
- [ ] Write Terraform plan workflow
- [ ] Create security scanning workflow (tfsec, checkov)
- [ ] Write Terraform docs generation workflow
- [ ] Create cost estimation workflow (Infracost)
- [ ] Write Terraform apply workflow
- [ ] Create drift detection workflow

### Build Tools (3 tasks)
- [ ] Write comprehensive Makefile for Terraform
- [ ] Create Taskfile.yml
- [ ] Write terraform wrapper scripts

### Release Automation (3 tasks)
- [ ] Create semantic versioning for modules
- [ ] Write changelog generation
- [ ] Create module release workflow

## Workflow Examples

### Terraform Validation
```yaml
name: Terraform Validate
on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.0
      
      - name: Terraform Format Check
        run: terraform fmt -check -recursive
      
      - name: Terraform Init
        run: terraform init -backend=false
      
      - name: Terraform Validate
        run: terraform validate
      
      - name: TFLint
        uses: terraform-linters/setup-tflint@v4
      
      - name: Run TFLint
        run: tflint --recursive
```

### Cost Estimation
```yaml
name: Infracost
on: [pull_request]

jobs:
  infracost:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: infracost/actions/setup@v3
        with:
          api-key: ${{ secrets.INFRACOST_API_KEY }}
      
      - name: Generate cost estimate
        run: |
          infracost breakdown --path . \
            --format json \
            --out-file /tmp/infracost.json
      
      - name: Post cost comment
        uses: infracost/actions/comment@v3
        with:
          path: /tmp/infracost.json
```

### Makefile for Terraform
```makefile
.PHONY: init plan apply destroy fmt validate

TERRAFORM_DIR ?= .

init: ## Initialize Terraform
	@cd $(TERRAFORM_DIR) && terraform init

plan: ## Run Terraform plan
	@cd $(TERRAFORM_DIR) && terraform plan

apply: ## Apply Terraform changes
	@cd $(TERRAFORM_DIR) && terraform apply

destroy: ## Destroy infrastructure
	@cd $(TERRAFORM_DIR) && terraform destroy

fmt: ## Format Terraform files
	@terraform fmt -recursive

validate: fmt ## Validate Terraform
	@cd $(TERRAFORM_DIR) && terraform validate
	@tflint --recursive
	@tfsec .

docs: ## Generate documentation
	@terraform-docs markdown table . --output-file README.md
```

## Acceptance Criteria
- All workflows are syntactically valid
- Workflows include proper OIDC authentication
- Cost estimation works
- Security scanning catches issues
- Documentation auto-updates

## Dependencies
- None (workflow definitions)

## Notes
- Use OIDC for AWS authentication
- Implement approval gates for apply
- Add Slack/Teams notifications
- Use matrix builds for modules
