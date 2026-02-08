# Terraform Style Guide

Style guide for Terraform code in aws-lab.

## Table of Contents

- [File Structure](#file-structure)
- [Naming Conventions](#naming-conventions)
- [Formatting](#formatting)
- [Variables](#variables)
- [Resources](#resources)
- [Outputs](#outputs)
- [Modules](#modules)
- [Best Practices](#best-practices)

---

## File Structure

### Standard Module Layout

```
modules/
├── ecs-service/
│   ├── main.tf           # Primary resources
│   ├── variables.tf      # Input variables
│   ├── outputs.tf        # Output values
│   ├── versions.tf       # Provider requirements
│   ├── locals.tf         # Local values
│   ├── data.tf           # Data sources
│   ├── iam.tf            # IAM resources (optional)
│   ├── README.md         # Documentation
│   └── doc.md            # Description for terraform-docs
```

### File Responsibilities

| File | Contents |
|------|----------|
| `main.tf` | Primary resources, module calls |
| `variables.tf` | All input variable declarations |
| `outputs.tf` | All output declarations |
| `versions.tf` | Required providers and versions |
| `locals.tf` | Local value computations |
| `data.tf` | Data source lookups |
| `iam.tf` | IAM roles, policies, attachments |

---

## Naming Conventions

### Resources

```hcl
# Format: aws_<service>_<resource>.<name>
# Name should be descriptive but concise

# Good
resource "aws_ecs_cluster" "main" {}
resource "aws_ecs_service" "api" {}
resource "aws_security_group" "ecs_tasks" {}
resource "aws_iam_role" "ecs_task_execution" {}

# Bad - too generic
resource "aws_ecs_cluster" "cluster" {}
resource "aws_security_group" "sg" {}

# Bad - too verbose
resource "aws_ecs_service" "api_backend_service_for_users" {}
```

### Variables

```hcl
# Use snake_case
# Be descriptive
# Group related variables with prefixes

variable "vpc_id" {}
variable "vpc_cidr" {}
variable "vpc_private_subnets" {}

variable "ecs_cluster_name" {}
variable "ecs_task_cpu" {}
variable "ecs_task_memory" {}

variable "container_image" {}
variable "container_port" {}
variable "container_environment" {}
```

### Outputs

```hcl
# Format: <resource>_<attribute>
output "cluster_id" {}
output "cluster_arn" {}
output "service_name" {}
output "task_definition_arn" {}
```

### Locals

```hcl
locals {
  # Computed values
  cluster_name = "${var.project_name}-${var.environment}"
  
  # Common tags
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}
```

---

## Formatting

### General Rules

- Use `terraform fmt` (enforced by pre-commit)
- Indent with 2 spaces
- Max line length: 120 characters
- Align `=` in blocks when it improves readability

### Examples

```hcl
# Good - aligned for readability
resource "aws_ecs_service" "main" {
  name            = local.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
}

# Good - complex blocks
resource "aws_ecs_task_definition" "main" {
  family                   = local.service_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name  = "app"
      image = var.container_image
      
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.main.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}
```

---

## Variables

### Variable Declarations

```hcl
variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  
  validation {
    condition     = length(var.cluster_name) <= 255
    error_message = "Cluster name must be 255 characters or less."
  }
}

variable "instance_types" {
  description = "List of EC2 instance types for capacity providers"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "enable_monitoring" {
  description = "Enable Container Insights monitoring"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
```

### Variable Ordering

1. Required variables (no default)
2. Optional variables with defaults
3. Group by logical category

---

## Resources

### Resource Ordering

1. Provider resources first
2. IAM resources
3. Networking resources
4. Storage resources
5. Compute resources
6. Application resources

### Tagging

```hcl
# Merge common tags with resource-specific tags
resource "aws_ecs_cluster" "main" {
  name = local.cluster_name
  
  tags = merge(
    local.common_tags,
    {
      Name = local.cluster_name
    },
    var.tags
  )
}
```

### Dependencies

```hcl
# Explicit dependencies when implicit isn't clear
resource "aws_ecs_service" "main" {
  # ... other config ...
  
  depends_on = [
    aws_iam_role_policy_attachment.execution,
    aws_lb_listener.main,
  ]
}
```

---

## Outputs

### Output Declarations

```hcl
output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

# Sensitive outputs
output "database_password" {
  description = "Database password"
  value       = random_password.db.result
  sensitive   = true
}
```

---

## Modules

### Module Calls

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.4.0"
  
  name = "${var.project_name}-${var.environment}"
  cidr = var.vpc_cidr
  
  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs
  
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = !var.high_availability
  
  tags = local.common_tags
}
```

### Module Structure

```hcl
# modules/ecs-service/versions.tf
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

---

## Best Practices

### 1. Use Remote State

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "aws-lab/ecs/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

### 2. Use Data Sources

```hcl
# Current AWS account
data "aws_caller_identity" "current" {}

# Available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Latest AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
```

### 3. Use Conditionals

```hcl
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? 1 : 0
  
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
}
```

### 4. Use for_each

```hcl
resource "aws_subnet" "private" {
  for_each = toset(var.availability_zones)
  
  vpc_id            = aws_vpc.main.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, index(var.availability_zones, each.value) + 10)
  
  tags = {
    Name = "${local.prefix}-private-${each.value}"
  }
}
```

### 5. Avoid Hardcoding

```hcl
# Bad
resource "aws_security_group_rule" "ingress" {
  cidr_blocks = ["10.0.0.0/16"]  # Hardcoded
}

# Good
resource "aws_security_group_rule" "ingress" {
  cidr_blocks = [aws_vpc.main.cidr_block]  # Dynamic
}
```

---

## Tooling

| Tool | Purpose | Config |
|------|---------|--------|
| terraform fmt | Formatting | Built-in |
| tflint | Linting | `.tflint.hcl` |
| tfsec | Security | `.tfsec.yml` |
| checkov | Policy | `.checkov.yml` |
| terraform-docs | Documentation | `.terraform-docs.yml` |
| infracost | Cost estimation | - |

---

*Last updated: 2026-01-31*
