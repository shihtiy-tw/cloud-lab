---
description: Switch cloud provider context
---

# cloud.switch

## Purpose

Switch the active cloud provider context for subsequent commands.

## CSP Support

**Supported Clouds**: `aws`, `gcp`, `azure`, `oracle`

## Usage

```bash
# Switch to AWS with profile
./scripts/cloud.switch.sh --cloud aws --profile staging --region us-west-2

# Switch to GCP with project
./scripts/cloud.switch.sh --cloud gcp --project my-project-123 --region us-central1

# Switch to Azure with subscription
./scripts/cloud.switch.sh --cloud azure --subscription my-subscription --rg my-rg

# Switch to Oracle with profile
./scripts/cloud.switch.sh --cloud oracle --profile DEFAULT --region us-ashburn-1

# Show current context
./scripts/cloud.switch.sh --show
```

## Parameters

- `--cloud` (required unless --show) - Cloud provider: `aws` | `gcp` | `azure` | `oracle`
- `--show` (optional) - Display current context
- CSP-specific parameters:
  - AWS: `--profile`, `--region`
  - GCP: `--project`, `--region`
  - Azure: `--subscription`, `--rg` (resource group)
  - Oracle: `--profile`, `--region`, `--compartment`

## Prerequisites

- CSP CLI tools installed
- Credentials configured
- Profiles/projects created

## Steps

1. Validate cloud provider
2. Check CSP CLI installed
3. Set environment variables
4. Update config files if needed
5. Verify connection
6. Display active context

## Context Storage

Stores context in `.cloud-context`:
```bash
CLOUD_PROVIDER=aws
AWS_PROFILE=staging
AWS_DEFAULT_REGION=us-west-2
```

## CSP-Specific Behavior

### AWS
```bash
export AWS_PROFILE=staging
export AWS_DEFAULT_REGION=us-west-2
aws sts get-caller-identity
```

### GCP
```bash
gcloud config set project my-project-123
gcloud config set compute/region us-central1
gcloud auth list
```

### Azure
```bash
az account set --subscription my-subscription
az account show
```

### Oracle
```bash
export OCI_CLI_PROFILE=DEFAULT
oci iam region list
```

## Safety Checks

- [ ] Validate CSP CLI installed
- [ ] Check credentials exist
- [ ] Verify connection successful
- [ ] Confirm context switch

## Related

- [cloud.provision](./cloud.provision.md) - Use switched context
- [cloud.cost](./cloud.cost.md) - View costs for context
