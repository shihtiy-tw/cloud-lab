# Testing Infrastructure

This directory contains the testing framework for aws-lab using Terratest.

## Structure

```
tests/
├── README.md             # This file
├── go.mod                # Go module definition
├── go.sum                # Go dependencies
├── helpers/              # Test helper functions
│   └── helpers.go
├── fixtures/             # Test fixtures (minimal Terraform configs)
│   └── basic/
│       └── main.tf
├── vpc_test.go           # VPC module tests
├── ecs_test.go           # ECS module tests
└── integration_test.go   # Integration tests
```

## Prerequisites

1. **Go 1.21+**
   ```bash
   go version
   # Should output: go version go1.21.x...
   ```

2. **Terraform 1.5+**
   ```bash
   terraform version
   ```

3. **AWS Credentials**
   ```bash
   aws sts get-caller-identity
   ```

## Setup

```bash
cd tests

# Initialize Go module
go mod init github.com/org/aws-lab/tests

# Download dependencies
go mod tidy
```

## Running Tests

### All Tests

```bash
go test -v ./...
```

### Specific Test

```bash
go test -v -run TestVPC ./...
```

### With Timeout

```bash
go test -v -timeout 30m ./...
```

### Skip Destroy (for debugging)

```bash
SKIP_DESTROY=true go test -v -run TestVPC ./...
```

## Writing Tests

### Basic Test Structure

```go
package test

import (
    "testing"

    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestMyModule(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../path/to/module",
        Vars: map[string]interface{}{
            "name":        "test",
            "environment": "dev",
        },
    })

    // Clean up resources when test completes
    defer terraform.Destroy(t, terraformOptions)

    // Deploy the module
    terraform.InitAndApply(t, terraformOptions)

    // Validate outputs
    output := terraform.Output(t, terraformOptions, "id")
    assert.NotEmpty(t, output)
}
```

### Using Fixtures

```go
func TestWithFixture(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "./fixtures/basic",
    })

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)
}
```

### Skipping Destroy

```go
func TestDebug(t *testing.T) {
    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../modules/vpc",
    })

    // Skip destroy for debugging
    if os.Getenv("SKIP_DESTROY") != "true" {
        defer terraform.Destroy(t, terraformOptions)
    }

    terraform.InitAndApply(t, terraformOptions)
}
```

## Test Categories

### Unit Tests (Plan Only)

```go
func TestVPCPlan(t *testing.T) {
    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../shared/vpc",
        PlanFilePath: "/tmp/vpc.plan",
    })

    // Just run plan, don't apply
    terraform.InitAndPlan(t, terraformOptions)
}
```

### Validation Tests

```go
func TestVPCValidate(t *testing.T) {
    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../shared/vpc",
    })

    terraform.Init(t, terraformOptions)
    terraform.Validate(t, terraformOptions)
}
```

### Integration Tests (Apply and Verify)

Run against real AWS resources (use with caution).

```go
func TestVPCIntegration(t *testing.T) {
    if testing.Short() {
        t.Skip("Skipping integration test in short mode")
    }

    // ... full test with apply
}
```

## Best Practices

1. **Always use `t.Parallel()`** for independent tests
2. **Always defer `terraform.Destroy()`** to clean up resources
3. **Use unique names** to avoid conflicts with parallel tests
4. **Tag test resources** for easy identification
5. **Use `testing.Short()`** to skip long-running tests

## CI Integration

```yaml
- name: Run Tests
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    AWS_REGION: us-west-2
  run: |
    cd tests
    go test -v -timeout 30m ./...
```

## Cleanup

If tests fail and leave resources behind:

```bash
# List resources with test tag
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Environment,Values=test

# Or use Terraform
cd tests/fixtures/basic
terraform destroy -auto-approve
```

---

*Last updated: 2026-01-31*
