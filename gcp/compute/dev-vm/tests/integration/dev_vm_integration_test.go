// Package test contains integration tests for gcp/compute/dev-vm.
//
// These create real cloud resources and cost money. Run them against a
// sandbox account only.
package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

// TestDevVmApply provisions the stack, asserts on its outputs, and destroys
// it again.
func TestDevVmApply(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../infrastructure",
		Vars: map[string]interface{}{
			"project_name": "terratest",
			"environment":  "test",
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// TODO: assert on outputs, e.g.
	// name := terraform.Output(t, terraformOptions, "name")
	// assert.NotEmpty(t, name)
}
