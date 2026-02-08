// Package helpers provides common test utilities for aws-lab Terratest tests.
package helpers

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

// TestConfig holds common test configuration
type TestConfig struct {
	Region      string
	Environment string
	UniqueID    string
}

// NewTestConfig creates a new test configuration with unique identifiers
func NewTestConfig() *TestConfig {
	return &TestConfig{
		Region:      GetEnvWithDefault("AWS_REGION", "us-west-2"),
		Environment: "test",
		UniqueID:    strings.ToLower(random.UniqueId()),
	}
}

// GetEnvWithDefault returns env var value or default
func GetEnvWithDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// SkipIfEnvNotSet skips the test if the specified env var is not set
func SkipIfEnvNotSet(t *testing.T, envVar string) {
	if os.Getenv(envVar) == "" {
		t.Skipf("Skipping test: %s not set", envVar)
	}
}

// SkipInShortMode skips integration tests in short mode
func SkipInShortMode(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}
}

// ShouldSkipDestroy returns true if SKIP_DESTROY env var is set
func ShouldSkipDestroy() bool {
	return os.Getenv("SKIP_DESTROY") == "true"
}

// CleanupOnDefer schedules terraform destroy unless SKIP_DESTROY is set
func CleanupOnDefer(t *testing.T, terraformOptions *terraform.Options) {
	if !ShouldSkipDestroy() {
		terraform.Destroy(t, terraformOptions)
	} else {
		t.Log("SKIP_DESTROY is set, skipping terraform destroy")
	}
}

// CommonTags returns common tags for test resources
func (c *TestConfig) CommonTags() map[string]string {
	return map[string]string{
		"Environment": c.Environment,
		"ManagedBy":   "terratest",
		"TestID":      c.UniqueID,
		"CreatedAt":   time.Now().Format(time.RFC3339),
	}
}

// ResourceName generates a unique resource name for testing
func (c *TestConfig) ResourceName(prefix string) string {
	return fmt.Sprintf("%s-%s-%s", prefix, c.Environment, c.UniqueID)
}

// DefaultTerraformOptions returns common terraform options
func (c *TestConfig) DefaultTerraformOptions(t *testing.T, terraformDir string) *terraform.Options {
	return terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: terraformDir,
		Vars: map[string]interface{}{
			"aws_region":  c.Region,
			"environment": c.Environment,
			"tags":        c.CommonTags(),
		},
		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION": c.Region,
		},
	})
}

// ValidateNotEmpty checks that a terraform output is not empty
func ValidateNotEmpty(t *testing.T, options *terraform.Options, outputName string) string {
	output := terraform.Output(t, options, outputName)
	if output == "" {
		t.Fatalf("Expected non-empty output for %s", outputName)
	}
	return output
}

// ValidateOutputContains checks that output contains expected substring
func ValidateOutputContains(t *testing.T, options *terraform.Options, outputName, expected string) {
	output := terraform.Output(t, options, outputName)
	if !strings.Contains(output, expected) {
		t.Fatalf("Expected output %s to contain %s, got: %s", outputName, expected, output)
	}
}
