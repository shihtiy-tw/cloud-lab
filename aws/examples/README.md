# Terraform Examples

This directory contains example Terraform configurations for aws-lab modules.

## Structure

```
examples/
├── README.md               # This file
├── ecs-basic/              # Simple ECS Fargate service
├── ecs-complete/           # Full ECS setup with all features
├── vpc-basic/              # Simple VPC configuration
└── complete-stack/         # Full infrastructure stack
```

## Usage

Each example is self-contained and can be deployed independently:

```bash
cd examples/ecs-basic

# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply

# Destroy when done
terraform destroy
```

## Examples Overview

### ecs-basic

Minimal ECS Fargate service:
- Single service
- Public subnets
- No HTTPS

```bash
cd examples/ecs-basic
terraform init && terraform apply
```

### ecs-complete

Full ECS setup:
- Multiple services
- ALB with HTTPS
- Auto-scaling
- Service discovery

```bash
cd examples/ecs-complete
terraform init && terraform apply
```

### vpc-basic

Simple VPC:
- 2 public subnets
- 2 private subnets
- NAT gateway

```bash
cd examples/vpc-basic
terraform init && terraform apply
```

## Variables

Most examples accept these common variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `us-west-2` |
| `project_name` | Project name | `example` |
| `environment` | Environment | `dev` |

Override with:

```bash
terraform apply -var="project_name=my-app" -var="environment=staging"
```

Or create `terraform.tfvars`:

```hcl
project_name = "my-app"
environment  = "staging"
aws_region   = "us-east-1"
```

## Cost Warning

These examples create AWS resources that **cost money**. Make sure to destroy resources when done:

```bash
terraform destroy
```

---

*Last updated: 2026-01-31*
