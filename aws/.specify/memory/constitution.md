# aws-lab Constitution

## Core Principles

### I. Terraform-First Infrastructure
- All infrastructure as Terraform code
- Use Terraform workspaces for region management
- Shared modules in `shared/modules/`
- State stored remotely (S3 + DynamoDB)

### II. CLI 12-Factor Compliance
Every script must:
1. **Help Always Works**: `--help` flag with usage info
2. **Flags Over Prompts**: Non-interactive by default
3. **Version Command**: `--version` reports version
4. **Stdout/Stderr**: Success → stdout, errors → stderr
5. **Exit Codes**: 0=success, 1=user error, 2=system error
6. **Dry Run**: `--dry-run` for preview when applicable
7. **Idempotent**: Safe to run multiple times

### III. Cost Consciousness
- Always tag resources for cost tracking
- Right-size by default, document scaling
- Cleanup automation for test resources
- Cost estimates before apply

### IV. Test-First Strategy
- Terratest for Go-based infrastructure tests
- Unit tests for modules
- Integration tests for scenarios
- Validate before apply

### V. Agent 12-Factor
1. **Own Prompts**: AGENTS.md per directory
2. **Explicit Tools**: Document available skills
3. **Context Boundaries**: Clear scope
4. **Human Contact**: Ask before destructive ops (especially destroy)

## 12-Factor for Infrastructure

1. **Codebase**: One repo, version-controlled
2. **Dependencies**: Provider versions pinned
3. **Config**: Variables and tfvars, never hardcoded
4. **Backing Services**: Data sources for existing resources
5. **Build/Release/Run**: Plan → Apply → Verify
6. **Processes**: Stateless Terraform runs
7. **Port Binding**: Security groups explicit
8. **Concurrency**: Scale via count/for_each
9. **Disposability**: Clean destroy support
10. **Dev/Prod Parity**: Workspaces for environments
11. **Logs**: CloudWatch/structured logging
12. **Admin**: One-off via targeted apply

## Structure Standards

```
{service}/
├── infrastructure/   # Terraform for base resources
├── scenarios/        # Usage patterns
├── tests/            # Terratest integration tests
└── utils/            # Helper scripts
```

## Script Template

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="1.0.0"
show_help() { ... }
show_version() { echo "$(basename "$0") version ${SCRIPT_VERSION}"; }
log_info() { echo "[INFO] $*" >&1; }
log_error() { echo "[ERROR] $*" >&2; }

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help; exit 0 ;;
        -v|--version) show_version; exit 0 ;;
        ...
    esac
done
```

## Terraform Standards

```hcl
# terraform.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Always tag resources
resource "aws_instance" "example" {
  tags = merge(var.common_tags, {
    Name = "${var.project}-${var.environment}"
  })
}
```

## Documentation Standards

Every scenario includes:
1. README.md with purpose, prerequisites, usage
2. Architecture diagram or description
3. Cost estimate section
4. Cleanup instructions (terraform destroy)

## Commit Conventions

```
feat(ecs/scenarios): add Fargate with EFS pattern
fix(shared/modules): correct VPC CIDR validation
docs(compute): add EC2 launch template guide
refactor(storage): CLI 12-factor compliance
test(rds): add Terratest for multi-AZ
```

## Governance

- Constitution supersedes all other practices
- All scripts must pass `--help` verification
- Cost tagging required on all resources
- Cleanup scripts required for test resources

**Version**: 1.0.0 | **Ratified**: 2026-01-30 | **Last Amended**: 2026-01-30
