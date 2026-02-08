---
id: spec-013
title: Developer Experience & Tooling
type: enhancement
priority: medium
status: planned
assignable: true
estimated_hours: 8
tags: [dx, terraform, tooling]
---

# Developer Experience & Tooling for aws-lab

## Overview
Improve developer experience for Terraform development.

## Tasks

### VS Code Configuration (5 tasks)
- [ ] Create .vscode/settings.json for Terraform
- [ ] Write .vscode/tasks.json for Terraform workflows
- [ ] Create .vscode/launch.json
- [ ] Write .vscode/extensions.json (HashiCorp Terraform, etc.)
- [ ] Create Terraform code snippets

### Development Scripts (4 tasks)
- [ ] Write environment setup script
- [ ] Create AWS credentials helper
- [ ] Write Terraform version manager wrapper
- [ ] Create workspace switcher script

### Developer Documentation (2 tasks)
- [ ] Create developer onboarding guide
- [ ] Write Terraform best practices guide

## Configuration Examples

### VS Code Settings
```json
{
  "[terraform]": {
    "editor.defaultFormatter": "hashicorp.terraform",
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
      "source.formatAll.terraform": true
    }
  },
  "terraform.languageServer": {
    "enabled": true,
    "args": []
  },
  "terraform.experimentalFeatures": {
    "validateOnSave": true
  },
  "files.associations": {
    "*.tfvars": "terraform",
    "*.tf": "terraform"
  }
}
```

### VS Code Extensions
```json
{
  "recommendations": [
    "hashicorp.terraform",
    "ms-azuretools.vscode-docker",
    "ms-vscode.makefile-tools",
    "golang.go",
    "redhat.vscode-yaml",
    "Github.copilot"
  ]
}
```

### Setup Script
```bash
#!/usr/bin/env bash
# scripts/setup-dev.sh

set -euo pipefail

echo "Setting up aws-lab development environment..."

# Check required tools
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 is not installed"
        return 1
    fi
    echo "✅ $1 is installed"
}

check_tool terraform
check_tool aws
check_tool tflint
check_tool terraform-docs
check_tool tfsec

echo "✅ All required tools are installed!"
```

## Acceptance Criteria
- VS Code workspace is configured
- All development scripts work
- Documentation is comprehensive
- Tool installation is automated

## Dependencies
- None

## Notes
- Support multiple Terraform versions
- Document AWS authentication methods
- Include troubleshooting guide
