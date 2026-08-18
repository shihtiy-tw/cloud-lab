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

- `--cloud` (required) - Cloud provider: `aws` | `gcp` | `azure` | `oracle`. Falls
  back to `CLOUD_PROVIDER` in `.cloud-context`
- `--service` (required) - Service path: `{category}/{service}` (e.g., `compute/ecs`)
- `--env` (required) - Environment: `dev` | `staging` | `test` | `prod`
- `--plan-only` (optional) - Show plan without applying
- `--destroy` (optional) - Destroy infrastructure
- `--auto-approve` (optional) - Skip the interactive prompt (never for prod destroy)
- `--confirm` (optional) - Required acknowledgement for prod and for `--destroy`
- `--var KEY=VALUE` (optional) - Additional Terraform variable; repeatable
- `--out <file>` (optional) - Save the plan file (default: a temp file, discarded)
- `--workspace <name>` (optional) - Select this Terraform workspace, creating it if
  needed. See the note below on why this is separate from `--env`

### `--env` selects tfvars, not a workspace

An earlier revision of this document described `--env` as selecting a Terraform
workspace. That is wrong for this repository and was never implemented that way.

26 files under `aws/` set `region = terraform.workspace`, so the workspace name
*is* the AWS region. A workspace named `dev` fails with `Invalid AWS Region: dev`.
Only a handful of stacks declare `variable "environment"` at all.

So `--env`:

- selects `<env>.tfvars` when that file exists, and
- passes `environment=<env>` only when the stack declares that variable.

Workspace selection is the explicit `--workspace` flag. The script warns when it
detects the `region = terraform.workspace` convention.

New stacks should take a real `region` variable and not copy that convention —
`{aws,gcp,azure}/compute/dev-vm` are the reference for how a stack should look.

### Multiple Terraform roots per service

A service may hold several Terraform roots (`aws/compute/ecs` has one per
scenario). When `--service` is ambiguous the candidates are listed, so pass a
deeper path:

```bash
./scripts/cloud.provision.sh --cloud aws \
  --service compute/ecs/infrastructure/cluster --env dev
```

## Prerequisites

- Terraform 1.5+ installed
- CSP CLI configured:
    - AWS: `aws configure` or IAM role
    - GCP: `gcloud auth login`
    - Azure: `az login`
    - Oracle: `oci setup config`
- Backend state configuration

No remote state backend exists in this repository yet, so the script warns about
local state on every run. That warning is accurate — treat it as a real gap, not
noise.

## Steps

1. Validate cloud provider and service path
2. Check CSP CLI authentication
3. Navigate to service directory
4. Initialize Terraform
5. Select/create the workspace, only when `--workspace` was given
6. Plan changes, saving the plan to a file
7. Apply **the saved plan file** (if not `--plan-only`), so what is applied is
   exactly what was reviewed
8. Output resource information

## CSP-Specific Behavior

| Cloud | Provider auth | Intended state backend | Path |
|-------|---------------|------------------------|------|
| AWS | profile / region | S3 + DynamoDB | `aws/{service}/` |
| GCP | project | GCS | `gcp/{service}/` |
| Azure | subscription | Azure Blob | `azure/{service}/` |
| Oracle | tenancy | OCI Object Storage | `oracle/{service}/` |

"Intended" is literal: none of these backends is configured yet. Every stack is
on local state today.

## Safety Checks

- [ ] Validate --cloud is supported
- [ ] Check CSP CLI authentication
- [ ] Verify service path exists
- [ ] For prod: require explicit `--confirm`, plus a prompt unless `--auto-approve`
- [ ] For `--destroy`: `--confirm` **and** typing an exact confirmation phrase
- [ ] For prod destroy: `--auto-approve` cannot skip the phrase

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid usage / arguments |
| 3 | Missing dependency |

## Related

- [cloud.test](./cloud.test.md) - Test infrastructure
- [cloud.cost](./cloud.cost.md) - Estimate costs
- [cloud.security](./cloud.security.md) - Security scan
