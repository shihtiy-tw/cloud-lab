# Quick Start Guide

Get started with aws-lab in 5 minutes.

## Prerequisites

Before you begin, ensure you have:

- **Terraform** (v1.5.0+)
- **AWS CLI** (v2.x)
- **TFLint** (latest)
- AWS credentials configured

Verify installation:
```bash
./scripts/setup-dev.sh --check-only
```

## Step 1: Configure AWS Credentials

```bash
# Configure default profile
aws configure

# Or use SSO
aws sso login --profile my-profile

# Verify identity
aws sts get-caller-identity
```

## Step 2: Set Up Backend (One-time)

Create S3 bucket and DynamoDB table for Terraform state:

```bash
# Create state bucket
aws s3api create-bucket \
  --bucket my-terraform-state-$(aws sts get-caller-identity --query Account --output text) \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-terraform-state-$(aws sts get-caller-identity --query Account --output text) \
  --versioning-configuration Status=Enabled

# Create lock table
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-west-2
```

## Step 3: Deploy an Environment

### Option A: Development Environment

```bash
cd environments/dev

# Initialize
terraform init

# Review the plan
terraform plan

# Apply
terraform apply
```

### Option B: Use a Module Directly

```bash
cd examples/ecs-basic

# Initialize
terraform init

# Plan with variables
terraform plan -var="project_name=my-app"

# Apply
terraform apply -var="project_name=my-app"
```

## Step 4: Verify Deployment

```bash
# List ECS clusters
aws ecs list-clusters

# Check ECS services
aws ecs list-services --cluster <cluster-name>

# Get outputs
terraform output
```

## Common Commands

```bash
# Initialize (download providers and modules)
terraform init

# Format code
terraform fmt -recursive

# Validate syntax
terraform validate

# Plan changes
terraform plan -out=tfplan

# Apply plan
terraform apply tfplan

# Destroy resources
terraform destroy

# Show current state
terraform show
```

## Project Structure

```
aws-lab/
├── compute/ecs/         # ECS modules
├── database/rds/        # RDS modules
├── storage/s3/          # S3 modules
├── shared/              # Shared modules (VPC, IAM)
├── environments/        # Environment configurations
│   ├── dev/
│   ├── staging/
│   └── prod/
└── examples/            # Usage examples
```

## Using Modules

### VPC Module

```hcl
module "vpc" {
  source = "../../shared/vpc"
  
  project_name = "my-app"
  environment  = "dev"
  vpc_cidr     = "10.0.0.0/16"
}
```

### ECS Service Module

```hcl
module "api_service" {
  source = "../../compute/ecs/service"
  
  name            = "api"
  cluster_id      = module.cluster.id
  container_image = "nginx:latest"
  container_port  = 80
  
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
}
```

## Development Workflow

```bash
# 1. Make changes
vim compute/ecs/service/main.tf

# 2. Format code
terraform fmt -recursive

# 3. Validate
terraform validate

# 4. Lint
tflint --recursive

# 5. Security check
tfsec .

# 6. Plan
terraform plan

# 7. Apply (to dev first)
terraform apply
```

## Next Steps

- [Architecture Overview](architecture/OVERVIEW.md)
- [Terraform Style Guide](standards/TERRAFORM_STYLE.md)
- [Tagging Standards](standards/TAGGING_STANDARDS.md)
- [Module Development](guides/MODULE_DEVELOPMENT.md)

## Getting Help

```bash
# Terraform help
terraform -help

# Module documentation
terraform-docs markdown table .

# Run validation
make lint

# Check costs
make cost
```

---

*Last updated: 2026-01-31*
