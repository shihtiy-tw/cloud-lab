---
description: Analyze and estimate cloud costs with CSP awareness
---

# cloud.cost

## Purpose

Analyze existing costs and estimate future costs for cloud resources across providers.

## CSP Support

**Supported Clouds**: `aws`, `gcp`, `azure`, `oracle`

## Usage

```bash
# AWS cost breakdown for last 30 days
./scripts/cloud.cost.sh --cloud aws --timeframe 30d --breakdown-by service

# GCP cost for specific project
./scripts/cloud.cost.sh --cloud gcp --project my-project --timeframe 7d

# Azure cost by resource group
./scripts/cloud.cost.sh --cloud azure --rg prod-rg --timeframe 30d

# Oracle cost analysis
./scripts/cloud.cost.sh --cloud oracle --compartment prod --timeframe 30d

# Estimate costs for Terraform plan
./scripts/cloud.cost.sh --cloud aws --estimate --plan terraform.plan

# Export to CSV
./scripts/cloud.cost.sh --cloud aws --timeframe 30d --export costs.csv
```

## Parameters

- `--cloud` (required) - Cloud provider: `aws` | `gcp` | `azure` | `oracle`
- `--timeframe` (optional) - Time period: `7d` | `30d` | `90d` | date range (default: 30d)
- `--breakdown-by` (optional) - Breakdown: `service` | `tag` | `region` | `account`
- `--estimate` (optional) - Estimate from Terraform plan
- `--plan` (optional) - Terraform plan file for estimation
- `--export` (optional) - Export to file (CSV/JSON)
- CSP-specific: `--project`, `--rg`, `--compartment`

## Prerequisites

- CSP cost management API access
- Billing read permissions
- For estimate: Infracost or CSP pricing API

## Steps

1. Validate cloud provider
2. Check billing API access
3. Fetch cost data
4. Apply filters and grouping
5. Format output
6. Export if requested

## CSP-Specific Behavior

### AWS (Cost Explorer)
```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-02-01 \
  --granularity MONTHLY \
  --metrics UnblendedCost
```

### GCP (Cloud Billing)
```bash
bq query --project_id=my-project \
  'SELECT * FROM billing_export.gcp_billing_export_v1'
```

### Azure (Cost Management)
```bash
az cost management query \
  --timeframe MonthToDate \
  --type ActualCost
```

### Oracle (Cost Analysis)
```bash
oci usage-api usage-summary list \
  --tenant-id $OCI_TENANCY \
  --time-usage-started 2026-01-01
```

## Output Format

```
Cloud Cost Report - AWS
Period: 2026-01-07 to 2026-02-07 (30 days)

Service           | Cost (USD) | % of Total
------------------|------------|------------
EC2               | $1,234.56  | 45%
RDS               | $567.89    | 21%
S3                | $234.56    | 9%
Lambda            | $123.45    | 5%
Other             | $543.21    | 20%
------------------|------------|------------
TOTAL             | $2,703.67  | 100%
```

## Safety Checks

- [ ] Validate billing API access
- [ ] Check timeframe is valid
- [ ] Verify cost data availability

## Related

- [cloud.provision](./cloud.provision.md) - Provision resources
- [cloud.security](./cloud.security.md) - Security status
