// Package test contains Terratest checks for aws/compute/dev-vm.
//
// Everything in this file is init + validate only, so it runs with no cloud
// credentials and creates nothing. Anything that needs an account lives in
// ../integration.
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

// TestDevVmValidatePinnedImage validates the branch taken when an AMI id is
// supplied instead of looked up. Both paths feed the same instance argument, and
// only one of them is exercised by the defaults.
func TestDevVmValidatePinnedImage(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../infrastructure",
		Vars: map[string]interface{}{
			"project_name": "terratest",
			"environment":  "test",
			"ami_id":       "ami-00000000000000000",
		},
	})

	terraform.Init(t, terraformOptions)
	terraform.Validate(t, terraformOptions)
}

// TestDevVmValidateOptionalResources validates the count/dynamic-guarded
// resources: the S3 transcript archive, the customer-managed key statements, and
// a disabled auto-stop schedule. These are the expressions most likely to break
// silently, because the default variable set never evaluates them.
func TestDevVmValidateOptionalResources(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../infrastructure",
		Vars: map[string]interface{}{
			"project_name":              "terratest",
			"environment":               "test",
			"enable_session_log_bucket": true,
			"kms_key_arn":               "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000",
			"auto_stop_enabled":         false,
			"idle_shutdown_enabled":     false,
			"single_nat_gateway":        false,
			"az_count":                  3,
		},
	})

	terraform.Init(t, terraformOptions)
	terraform.Validate(t, terraformOptions)
}
