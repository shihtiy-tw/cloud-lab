// Package test contains Terratest checks for aws/compute/dev-vm.
package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

// TestDevVmValidate initialises and validates the stack without creating
// anything, so it is safe to run without cloud credentials.
func TestDevVmValidate(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../infrastructure",
		Vars: map[string]interface{}{
			"project_name": "terratest",
			"environment":  "test",
		},
	})

	terraform.Init(t, terraformOptions)
	terraform.Validate(t, terraformOptions)
}
