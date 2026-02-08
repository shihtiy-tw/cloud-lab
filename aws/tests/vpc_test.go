// Package test contains Terratest tests for aws-lab modules.
package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"

	"github.com/org/aws-lab/tests/helpers"
)

// TestVPCValidate validates the VPC module configuration
func TestVPCValidate(t *testing.T) {
	t.Parallel()

	config := helpers.NewTestConfig()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../shared/vpc",
		Vars: map[string]interface{}{
			"project_name": config.ResourceName("test"),
			"environment":  config.Environment,
			"vpc_cidr":     "10.0.0.0/16",
		},
	})

	terraform.Init(t, terraformOptions)
	terraform.Validate(t, terraformOptions)
}

// TestVPCPlan creates a plan for the VPC module
func TestVPCPlan(t *testing.T) {
	t.Parallel()

	config := helpers.NewTestConfig()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../shared/vpc",
		Vars: map[string]interface{}{
			"project_name": config.ResourceName("test"),
			"environment":  config.Environment,
			"vpc_cidr":     "10.0.0.0/16",
			"tags":         config.CommonTags(),
		},
	})

	terraform.Init(t, terraformOptions)
	plan := terraform.InitAndPlanAndShowWithStruct(t, terraformOptions)

	// Verify resources will be created
	assert.Greater(t, len(plan.ResourcePlannedValuesMap), 0, "Expected resources to be planned")
}

// TestVPCIntegration deploys and verifies VPC resources
func TestVPCIntegration(t *testing.T) {
	// Skip in short mode
	helpers.SkipInShortMode(t)

	t.Parallel()

	config := helpers.NewTestConfig()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../shared/vpc",
		Vars: map[string]interface{}{
			"project_name": config.ResourceName("test"),
			"environment":  config.Environment,
			"vpc_cidr":     "10.0.0.0/16",
			"tags":         config.CommonTags(),
		},
	})

	// Schedule cleanup
	defer helpers.CleanupOnDefer(t, terraformOptions)

	// Deploy
	terraform.InitAndApply(t, terraformOptions)

	// Validate outputs
	vpcID := helpers.ValidateNotEmpty(t, terraformOptions, "vpc_id")
	assert.Contains(t, vpcID, "vpc-", "VPC ID should start with vpc-")

	// Validate CIDR
	vpcCIDR := terraform.Output(t, terraformOptions, "vpc_cidr")
	assert.Equal(t, "10.0.0.0/16", vpcCIDR)

	// Validate subnets were created
	privateSubnets := terraform.OutputList(t, terraformOptions, "private_subnet_ids")
	assert.Greater(t, len(privateSubnets), 0, "Should have private subnets")

	publicSubnets := terraform.OutputList(t, terraformOptions, "public_subnet_ids")
	assert.Greater(t, len(publicSubnets), 0, "Should have public subnets")
}
