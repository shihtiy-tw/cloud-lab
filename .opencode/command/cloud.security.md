---
description: Run security scans on infrastructure code
---

# cloud.security

## Purpose

Run security scans using tfsec, checkov, and CSP-specific security tools.

## CSP Support

**Supported Clouds**: `aws`, `gcp`, `azure`, `oracle`

## Usage

```bash
# Scan AWS service
./scripts/cloud.security.sh --cloud aws --service compute/ecs

# Scan all services for a cloud
./scripts/cloud.security.sh --cloud gcp --all

# Scan with specific tool
./scripts/cloud.security.sh --cloud aws --service networking/vpc --tool tfsec

# Generate report
./scripts/cloud.security.sh --cloud azure --all --report security-report.html

# Fail on specific severity
./scripts/cloud.security.sh --cloud aws --service compute/ecs --min-severity high
```

## Parameters

- `--cloud` (required) - Cloud provider: `aws` | `gcp` | `azure` | `oracle`
- `--service` (optional) - Service path to scan
- `--all` (optional) - Scan all services for cloud
- `--tool` (optional) - Specific tool: `tfsec` | `checkov` | `trivy` | `all` (default: all)
- `--report` (optional) - Generate HTML/JSON report
- `--min-severity` (optional) - Minimum severity: `low` | `medium` | `high` | `critical`

## Prerequisites

- Security tools installed:
  - tfsec
  - checkov
  - trivy (for containers)
- Terraform files accessible

## Steps

1. Validate cloud and service
2. Collect Terraform files
3. Run security scanners
4. Aggregate results
5. Generate report
6. Return exit code based on findings

## Tools Used

### tfsec
Static analysis for Terraform - fast, focused on security misconfigurations.

### checkov
Policy-as-code scanner - comprehensive, supports many frameworks.

### trivy
Container and IaC scanner - good for container security.

## CSP-Specific Checks

### AWS
- S3 bucket policies
- IAM permissions
- Security group rules
- KMS key policies
- VPC configurations

### GCP
- IAM bindings
- Firewall rules
- Storage bucket ACLs
- KMS key access

### Azure
- RBAC assignments
- NSG rules
- Key Vault access
- Storage account security

### Oracle
- Policy statements
- Security lists
- Vault secrets
- Object Storage policies

## Output Format

```
Security Scan Results - AWS compute/ecs
=====================================

tfsec
-----
CRITICAL: 0
HIGH: 2
MEDIUM: 5
LOW: 8

[HIGH] aws_security_group.ecs_tasks (line 45)
  - Security group allows ingress from 0.0.0.0/0

checkov
-------
Passed: 45
Failed: 7
Skipped: 3
```

## Safety Checks

- [ ] Validate tools are installed
- [ ] Check service path exists
- [ ] Verify Terraform files present

## Related

- [cloud.provision](./cloud.provision.md) - Fix and redeploy
- [cloud.test](./cloud.test.md) - Integration testing
