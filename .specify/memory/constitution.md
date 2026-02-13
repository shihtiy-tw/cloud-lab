# cloud-lab Constitution

## Core Principles

### 1. Multi-Cloud First
All patterns should be cloud-agnostic when possible.
- Use Terraform as the primary IaC tool
- Abstract common patterns in `shared/modules/`
- CSP-specific code in `{cloud}/` directories

### 2. Infrastructure as Code
All infrastructure is version controlled and reproducible.
- Terraform for declarative infrastructure
- State stored remotely (S3/GCS/Blob/Object Storage)
- No manual console changes

### 3. Security by Default
Security is a first-class concern.
- Run tfsec/checkov on all changes
- Use least-privilege IAM/RBAC
- Encrypt at rest and in transit
- No public exposure by default

### 4. Cost Awareness
Monitor and optimize cloud costs.
- Tag all resources with cost centers
- Review cost estimates before apply
- Clean up unused resources

---

## Naming Conventions

### Terraform
- **Modules**: `snake_case` → `ecs_cluster`, `vpc_network`
- **Resources**: `snake_case` → `aws_ecs_cluster.main`
- **Variables**: `snake_case` → `vpc_cidr_block`
- **Files**: `lower-kebab.tf` → `main.tf`, `variables.tf`

### Cloud Resources

| Component | Pattern | Example |
|-----------|---------|---------|
| VPC/VNet | `{project}-{env}-vpc` | `myapp-prod-vpc` |
| Subnet | `{project}-{env}-{az}-{type}` | `myapp-prod-us-west-2a-public` |
| Security Group | `{project}-{env}-{service}-sg` | `myapp-prod-api-sg` |
| Instance | `{project}-{env}-{service}-{n}` | `myapp-prod-web-01` |
| S3 Bucket | `{org}-{project}-{env}-{purpose}` | `acme-myapp-prod-assets` |
| IAM Role | `{project}-{env}-{service}-role` | `myapp-prod-ecs-task-role` |

### Tags (Required)

| Tag | Description | Example |
|-----|-------------|---------|
| `Environment` | Deployment environment | `prod`, `staging`, `dev` |
| `Project` | Project name | `myapp` |
| `Owner` | Team or individual | `platform-team` |
| `CostCenter` | Billing allocation | `engineering` |
| `ManagedBy` | IaC tool | `terraform` |

---

## Best Practices

### Terraform

- Use remote state with locking
- Pin provider versions
- Use modules for reusability
- Validate with `terraform validate`
- Format with `terraform fmt`

### Security

- Enable CSP-native security scanning
- Use managed secrets services (Secrets Manager, Secret Manager, Key Vault)
- Enable audit logging (CloudTrail, Cloud Audit, Activity Log)
- Apply principle of least privilege

### Testing

- Write Terratest for all modules
- Run integration tests in isolated accounts
- Clean up test resources automatically
- Use naming prefixes for test resources

---

## Safety Rules

### Never Do
- ❌ Apply to prod without plan review
- ❌ Commit credentials or secrets
- ❌ Use `*` in IAM policies without justification
- ❌ Expose resources to 0.0.0.0/0 without approval
- ❌ Skip security scans

### Always Do
- ✅ Run `terraform plan` before apply
- ✅ Use remote state with locking
- ✅ Tag all resources
- ✅ Run security scans (tfsec, checkov)
- ✅ Document infrastructure decisions

### Require Confirmation For
- 🔐 Production applies
- 🔐 Resource destruction
- 🔐 IAM policy changes
- 🔐 Network security changes
- 🔐 Cross-cloud operations

---

## Common Patterns

### Module Interface

```hcl
# variables.tf
variable "environment" {
  description = "Deployment environment"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "tags" {
  description = "Additional tags to apply"
  type        = map(string)
  default     = {}
}

# outputs.tf
output "id" {
  description = "Resource identifier"
  value       = aws_resource.main.id
}
```

### State Backend Pattern

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket"
    key            = "cloud-lab/{service}/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

---

## CSP-Specific Notes

### AWS
- Use AWS Organizations for multi-account
- Enable GuardDuty and SecurityHub
- Use EKS for Kubernetes workloads
- Prefer Fargate for serverless containers

### GCP
- Use projects for isolation
- Enable Security Command Center
- Use GKE Autopilot for managed K8s
- Prefer Cloud Run for serverless

### Azure
- Use Resource Groups for organization
- Enable Microsoft Defender for Cloud
- Use AKS for Kubernetes workloads
- Prefer Container Apps for serverless

### Oracle
- Use Compartments for isolation
- Enable Cloud Guard
- Use OKE for Kubernetes workloads
- Prefer Functions for serverless

---

## Related

- [AGENTS.md](../AGENTS.md) - Agent context
- [README.md](../README.md) - Project documentation
