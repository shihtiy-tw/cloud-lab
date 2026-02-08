# Tagging Standards for AWS Resources

All AWS resources in aws-lab must be properly tagged for cost allocation, organization, and governance.

## Required Tags

Every resource **MUST** have these tags:

| Tag | Description | Example |
|-----|-------------|---------|
| `Environment` | Deployment environment | `dev`, `staging`, `prod` |
| `Project` | Project or application name | `my-app`, `api-service` |
| `ManagedBy` | How the resource is managed | `terraform`, `cloudformation` |

## Recommended Tags

These tags **SHOULD** be included where applicable:

| Tag | Description | Example |
|-----|-------------|---------|
| `Owner` | Team or individual owner | `platform-team`, `john.doe` |
| `CostCenter` | Cost allocation code | `engineering`, `12345` |
| `Application` | Specific application | `web-frontend`, `api-backend` |
| `Component` | Infrastructure component | `database`, `cache`, `compute` |
| `Automation` | Automation that manages it | `github-actions`, `jenkins` |

## Implementation

### In Terraform

```hcl
# Define common tags in locals
locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
}

# Apply to resources
resource "aws_ecs_cluster" "main" {
  name = local.cluster_name
  
  tags = merge(
    local.common_tags,
    {
      Name      = local.cluster_name
      Component = "compute"
    }
  )
}

# With additional custom tags
resource "aws_ecs_service" "api" {
  # ... config ...
  
  tags = merge(
    local.common_tags,
    var.additional_tags,
    {
      Name        = "api-service"
      Application = "api"
      Component   = "compute"
    }
  )
}
```

### Default Tags Provider

```hcl
# In versions.tf or providers.tf
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}
```

## Tag Values

### Environment Values

| Value | Description |
|-------|-------------|
| `dev` | Development |
| `staging` | Staging/QA |
| `prod` | Production |
| `sandbox` | Experimentation |
| `demo` | Demonstrations |

### ManagedBy Values

| Value | Description |
|-------|-------------|
| `terraform` | Managed by Terraform |
| `cloudformation` | Managed by CloudFormation |
| `cdk` | Managed by AWS CDK |
| `manual` | Created manually (discourage) |
| `pulumi` | Managed by Pulumi |

## Tag Enforcement

### AWS Organizations Tag Policies

```json
{
  "tags": {
    "Environment": {
      "tag_key": {
        "@@assign": "Environment"
      },
      "tag_value": {
        "@@assign": [
          "dev",
          "staging",
          "prod",
          "sandbox"
        ]
      }
    }
  }
}
```

### Pre-commit Check

Tags are validated by tflint with these rules:
- `aws_*_missing_tags` - Ensures required tags exist
- Custom rules in `.tflint.hcl`

## Cost Allocation

### Enable Cost Allocation Tags

In AWS Billing console, activate these tags for cost allocation:

1. Go to AWS Billing → Cost Allocation Tags
2. Select tags: `Environment`, `Project`, `CostCenter`, `Application`
3. Click "Activate"

### Cost Explorer Grouping

Use these tags to group and filter costs in AWS Cost Explorer.

## Best Practices

1. **Be Consistent**: Use the same tag keys across all resources
2. **Use Lowercase**: Tag values should be lowercase (except proper nouns)
3. **Avoid Spaces**: Use hyphens or underscores instead
4. **Keep It Simple**: Don't over-tag; focus on useful categorization
5. **Automate**: Always use `default_tags` provider block
6. **Validate**: Use tflint to check for missing tags

## AWS Tag Limits

- Maximum 50 user-created tags per resource
- Key length: 1-128 characters
- Value length: 0-256 characters
- Keys and values are case-sensitive
- `aws:` prefix is reserved

---

*Last updated: 2026-01-31*
