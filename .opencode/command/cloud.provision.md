---
description: Provision cloud infrastructure using Terraform with CSP awareness
---

# cloud.provision

## Purpose

Provision cloud infrastructure resources using Terraform with automatic CSP detection and environment handling.

## CSP Support

**Supported Clouds**: `aws`, `gcp`, `azure`, `oracle`

## Usage

```bash
# AWS ECS deployment
./scripts/cloud.provision.sh --cloud aws --service compute/ecs --env dev

# GCP GKE deployment
./scripts/cloud.provision.sh --cloud gcp --service compute/gke --env staging

# Azure AKS deployment
./scripts/cloud.provision.sh --cloud azure --service compute/aks --env test

# Oracle OKE deployment
./scripts/cloud.provision.sh --cloud oracle --service compute/oke --env prod

# Dry run (plan only)
./scripts/cloud.provision.sh --cloud aws --service networking/vpc --env dev --plan-only

# Destroy resources
./scripts/cloud.provision.sh --cloud aws --service compute/ecs --env dev --destroy
```

## Parameters

- `--cloud` (required) - Cloud provider: `aws` | `gcp` | `azure` | `oracle`
- `--service` (required) - Service path: `{category}/{service}` (e.g., `compute/ecs`)
- `--env` (required) - Environment: `dev` | `staging` | `test` | `prod`
- `--plan-only` (optional) - Show plan without applying
- `--destroy` (optional) - Destroy infrastructure
- `--auto-approve` (optional) - Skip confirmation (not for prod)
- `--var` (optional) - Additional Terraform variables

## Prerequisites

- Terraform 1.5+ installed
- CSP CLI configured:
  - AWS: `aws configure` or IAM role
  - GCP: `gcloud auth login`
  - Azure: `az login`
  - Oracle: `oci setup config`
- Backend state configuration

## Steps

1. Validate cloud provider and service path
2. Check CSP CLI authentication
3. Navigate to service directory
4. Initialize Terraform
5. Select/create workspace
6. Plan changes
7. Apply (if not --plan-only)
8. Output resource information

## CSP-Specific Behavior

### AWS
- Uses AWS provider with profile/region
- State backend: S3 + DynamoDB
- Path: `aws/{service}/`

### GCP
- Uses Google provider with project
- State backend: GCS
- Path: `gcp/{service}/`

### Azure
- Uses AzureRM provider with subscription
- State backend: Azure Blob
- Path: `azure/{service}/`

### Oracle
- Uses OCI provider with tenancy
- State backend: OCI Object Storage
- Path: `oracle/{service}/`

## Safety Checks

- [ ] Validate --cloud is supported
- [ ] Check CSP CLI authentication
- [ ] Verify service path exists
- [ ] For prod: Require explicit --confirm
- [ ] For --destroy: Double confirmation required

## Related

- [cloud.test](./cloud.test.md) - Test infrastructure
- [cloud.cost](./cloud.cost.md) - Estimate costs
- [cloud.security](./cloud.security.md) - Security scan
