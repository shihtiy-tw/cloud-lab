---
description: Generate documentation for infrastructure code
---

# cloud.docs

## Purpose

Generate documentation using terraform-docs and README updates.

## CSP Support

**Supported Clouds**: `aws`, `gcp`, `azure`, `oracle`

## Usage

```bash
# Generate docs for specific service
./scripts/cloud.docs.sh --cloud aws --service compute/ecs

# Generate docs for all AWS services
./scripts/cloud.docs.sh --cloud aws --all

# Generate with specific format
./scripts/cloud.docs.sh --cloud gcp --service compute/gke --format markdown

# Update existing README
./scripts/cloud.docs.sh --cloud azure --service compute/aks --update-readme
```

## Parameters

- `--cloud` (required) - Cloud provider: `aws` | `gcp` | `azure` | `oracle`
- `--service` (optional) - Service path to document
- `--all` (optional) - Generate for all services
- `--format` (optional) - Output format: `markdown` | `json` | `asciidoc` (default: markdown)
- `--update-readme` (optional) - Update README.md in place
- `--output` (optional) - Custom output file

## Prerequisites

- terraform-docs installed
- .terraform-docs.yml config (optional)
- Terraform files with descriptions

## Steps

1. Validate cloud and service
2. Find Terraform files
3. Run terraform-docs
4. Apply formatting
5. Write output or update README

## Generated Content

### Inputs Table
| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| vpc_id | VPC ID | string | n/a | yes |

### Outputs Table
| Name | Description |
|------|-------------|
| cluster_id | ECS cluster ID |

### Resources List
- aws_ecs_cluster
- aws_ecs_service
- aws_ecs_task_definition

## Configuration

Uses `.terraform-docs.yml` if present:
```yaml
formatter: markdown table
header-from: doc-header.md
sections:
  show:
    - inputs
    - outputs
    - resources
output:
  file: README.md
  mode: inject
```

## Safety Checks

- [ ] Validate terraform-docs installed
- [ ] Check service path exists
- [ ] Verify Terraform files present
- [ ] Backup README if updating

## Related

- [cloud.provision](./cloud.provision.md) - Provision documented resources
- [cloud.init](./cloud.init.md) - Initialize new service with docs
