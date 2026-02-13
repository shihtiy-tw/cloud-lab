---
description: Run Terratest and infrastructure tests with CSP awareness
---

# cloud.test

## Purpose

Execute infrastructure tests using Terratest with automatic CSP and service detection.

## CSP Support

**Supported Clouds**: `aws`, `gcp`, `azure`, `oracle`

## Usage

```bash
# Run all tests for AWS ECS
./scripts/cloud.test.sh --cloud aws --service compute/ecs

# Run specific test suite
./scripts/cloud.test.sh --cloud aws --service compute/ecs --suite integration

# Run with verbose output
./scripts/cloud.test.sh --cloud gcp --service compute/gke --verbose

# Run with timeout
./scripts/cloud.test.sh --cloud azure --service compute/aks --timeout 30m
```

## Parameters

- `--cloud` (required) - Cloud provider: `aws` | `gcp` | `azure` | `oracle`
- `--service` (required) - Service path: `{category}/{service}`
- `--suite` (optional) - Test suite: `unit` | `integration` | `all` (default: all)
- `--verbose` (optional) - Detailed test output
- `--timeout` (optional) - Test timeout (default: 10m)
- `--parallel` (optional) - Parallel test execution count

## Prerequisites

- Go 1.21+ installed
- Terratest installed
- CSP CLI configured
- Test infrastructure credentials

## Steps

1. Validate cloud provider and service
2. Navigate to test directory
3. Run go test with Terratest
4. Collect and format results
5. Clean up test resources

## Test Directory Structure

```
{cloud}/{service}/tests/
├── unit/
│   └── *_test.go
├── integration/
│   └── *_test.go
└── fixtures/
    └── *.tf
```

## CSP-Specific Behavior

### AWS
- Uses AWS SDK for resource validation
- Checks CloudWatch for logs
- Validates IAM permissions

### GCP
- Uses Google Cloud SDK
- Validates Cloud Logging
- Checks IAM bindings

### Azure
- Uses Azure SDK for Go
- Validates Azure Monitor
- Checks RBAC roles

### Oracle
- Uses OCI SDK
- Validates OCI Logging
- Checks policies

## Safety Checks

- [ ] Validate test credentials separate from prod
- [ ] Check test resource naming conventions
- [ ] Verify cleanup runs on failure
- [ ] Confirm test isolation

## Related

- [cloud.provision](./cloud.provision.md) - Create test infrastructure
- [cloud.security](./cloud.security.md) - Security testing
