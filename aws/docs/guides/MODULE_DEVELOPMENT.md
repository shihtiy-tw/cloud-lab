# Module Development Guide

Guide for creating Terraform modules in aws-lab.

## Prerequisites

- Terraform 1.5.0+
- Understanding of AWS services
- Familiarity with Terraform HCL

## Quick Start

1. Create module directory:
   ```bash
   mkdir -p compute/my-service
   cd compute/my-service
   ```

2. Create required files:
   ```bash
   touch main.tf variables.tf outputs.tf versions.tf README.md
   ```

3. Implement the module (see templates below)

4. Generate documentation:
   ```bash
   terraform-docs markdown table . --output-file README.md
   ```

## Module Structure

```
modules/<category>/<module-name>/
├── main.tf           # Primary resources
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── versions.tf       # Provider requirements
├── locals.tf         # Local computations (optional)
├── data.tf           # Data sources (optional)
├── iam.tf            # IAM resources (optional)
├── README.md         # Documentation (auto-generated)
└── doc.md            # Module description for terraform-docs
```

## File Templates

### versions.tf

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
```

### variables.tf

```hcl
################################################################################
# Required Variables
################################################################################

variable "name" {
  description = "Name of the resource"
  type        = string

  validation {
    condition     = length(var.name) <= 64
    error_message = "Name must be 64 characters or less."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

################################################################################
# Optional Variables
################################################################################

variable "tags" {
  description = "Additional tags to apply"
  type        = map(string)
  default     = {}
}

variable "enable_feature" {
  description = "Enable optional feature"
  type        = bool
  default     = false
}
```

### main.tf

```hcl
################################################################################
# Local Values
################################################################################

locals {
  name_prefix = "${var.name}-${var.environment}"

  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      Module      = "my-module"
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

################################################################################
# Resources
################################################################################

resource "aws_resource" "main" {
  name = local.name_prefix

  # Configuration here

  tags = local.common_tags
}

################################################################################
# Conditional Resources
################################################################################

resource "aws_optional_resource" "feature" {
  count = var.enable_feature ? 1 : 0

  name = "${local.name_prefix}-feature"

  tags = local.common_tags
}
```

### outputs.tf

```hcl
################################################################################
# Outputs
################################################################################

output "id" {
  description = "ID of the resource"
  value       = aws_resource.main.id
}

output "arn" {
  description = "ARN of the resource"
  value       = aws_resource.main.arn
}

output "name" {
  description = "Name of the resource"
  value       = aws_resource.main.name
}

# Conditional output
output "feature_id" {
  description = "ID of the optional feature (if enabled)"
  value       = var.enable_feature ? aws_optional_resource.feature[0].id : null
}
```

### doc.md

```markdown
This module creates an AWS resource with best practices.

## Features

- Feature 1
- Feature 2
- Optional: Feature 3

## Usage

\`\`\`hcl
module "example" {
  source = "../../category/my-module"

  name        = "my-resource"
  environment = "dev"
}
\`\`\`
```

## Best Practices

### 1. Variable Validation

```hcl
variable "instance_type" {
  type = string
  
  validation {
    condition     = can(regex("^t3\\.(micro|small|medium)$", var.instance_type))
    error_message = "Instance type must be t3.micro, t3.small, or t3.medium."
  }
}
```

### 2. Use for_each Over count

```hcl
# Good - for_each with map
variable "subnets" {
  type = map(object({
    cidr = string
    az   = string
  }))
}

resource "aws_subnet" "main" {
  for_each = var.subnets

  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = {
    Name = each.key
  }
}

# Less ideal - count with list
resource "aws_subnet" "main" {
  count = length(var.subnet_cidrs)
  # ...
}
```

### 3. Conditional Resources

```hcl
# Create only if enabled
resource "aws_resource" "optional" {
  count = var.create_optional ? 1 : 0
  # ...
}

# Reference conditional resource
output "optional_id" {
  value = var.create_optional ? aws_resource.optional[0].id : null
}
```

### 4. Data Sources

```hcl
# Get current region
data "aws_region" "current" {}

# Get current account
data "aws_caller_identity" "current" {}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}
```

### 5. IAM Best Practices

```hcl
# Use data source for policy document
data "aws_iam_policy_document" "main" {
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    
    resources = [
      aws_s3_bucket.main.arn,
      "${aws_s3_bucket.main.arn}/*",
    ]
  }
}

resource "aws_iam_policy" "main" {
  name   = "${local.name_prefix}-policy"
  policy = data.aws_iam_policy_document.main.json
}
```

## Testing

### Terratest Example

```go
package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestModule(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../examples/basic",
		Vars: map[string]interface{}{
			"name":        "test",
			"environment": "dev",
		},
	})

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	// Validate outputs
	id := terraform.Output(t, terraformOptions, "id")
	assert.NotEmpty(t, id)
}
```

## Checklist

Before publishing a module:

- [ ] All variables have descriptions and types
- [ ] Required variables have validation
- [ ] Outputs are documented
- [ ] README.md is auto-generated
- [ ] Example usage provided
- [ ] Follows naming conventions
- [ ] TFLint passes
- [ ] tfsec passes
- [ ] Tested with `terraform plan`

## See Also

- [Terraform Style Guide](../standards/TERRAFORM_STYLE.md)
- [Tagging Standards](../standards/TAGGING_STANDARDS.md)
- [Architecture Overview](../architecture/OVERVIEW.md)

---

*Last updated: 2026-01-31*
