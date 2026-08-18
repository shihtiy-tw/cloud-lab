// Package test contains Terratest checks for gcp/compute/dev-vm.
//
// Everything in this file must pass with no cloud credentials configured. That
// is not a nicety: the security properties this stack exists to guarantee are
// the sort of thing that gets "helpfully" edited, and a guard that only runs
// when someone has a GCP project handy is a guard that never runs.
package test

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	devVMDir     = "../../infrastructure"
	networkDir   = "../../../../shared/modules/network"
	iapRangeCIDR = "35.235.240.0/20"
)

// TestDevVmValidate initialises and validates the stack without creating
// anything, so it is safe to run without cloud credentials.
func TestDevVmValidate(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: devVMDir,
		Vars: map[string]interface{}{
			"project_name": "terratest",
			"environment":  "test",
			"project_id":   "terratest-validate-only",
		},
	})

	terraform.Init(t, terraformOptions)
	terraform.Validate(t, terraformOptions)
}

// TestNetworkModuleValidate validates the VPC module on its own. The dev VM
// consumes it, but a module that only ever gets validated through one caller
// hides errors in the paths that caller does not exercise (here: the
// enable_cloud_nat = false branch).
func TestNetworkModuleValidate(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: networkDir,
		Vars: map[string]interface{}{
			"project_name": "terratest",
			"environment":  "test",
			"project_id":   "terratest-validate-only",
		},
	})

	terraform.Init(t, terraformOptions)
	terraform.Validate(t, terraformOptions)
}

// TestInstanceHasNoAccessConfig is the single most important assertion in this
// repository's GCP tree.
//
// An `access_config` block inside `network_interface` is what assigns an
// external IP address. Its absence is the requirement -- "do not open SSH to the
// public network" -- and it is invisible: nothing about the configuration looks
// wrong once someone has added one. So this test reads the source and fails on
// the block's presence, rather than waiting for an apply to reveal it.
func TestInstanceHasNoAccessConfig(t *testing.T) {
	t.Parallel()

	source := readTerraform(t, filepath.Join(devVMDir, "main.tf"))

	// Deliberately matches the block opener, so the prose comment in main.tf
	// explaining why the block is absent does not trip the test.
	accessConfigBlock := regexp.MustCompile(`(?m)^\s*access_config\s*{`)

	assert.NotRegexp(t, accessConfigBlock, source,
		"the dev VM must not declare an access_config block: that is what assigns a public IP, and its absence is the security requirement")
}

// TestOnlySshIngressIsIap asserts the second property: the one rule that opens
// port 22 accepts traffic only from Google's IAP forwarding range.
func TestOnlySshIngressIsIap(t *testing.T) {
	t.Parallel()

	// Comments stripped: the IAP rule's own comment names 0.0.0.0/0 to warn against
	// adding it, and the warning is worth more than a simpler test.
	source := stripComments(readTerraform(t, filepath.Join(networkDir, "main.tf")))

	require.Contains(t, source, `source_ranges = ["`+iapRangeCIDR+`"]`,
		"the SSH ingress rule must source from the IAP forwarding range")

	// Any firewall rule with an `allow` block is an ingress path. None of them may
	// accept the internet.
	for _, block := range firewallBlocks(source) {
		if !strings.Contains(block, "allow {") {
			continue
		}

		assert.NotContains(t, block, "0.0.0.0/0",
			"a firewall rule with an allow block must never source from 0.0.0.0/0; only %s is permitted", iapRangeCIDR)
		assert.Contains(t, block, iapRangeCIDR,
			"every allow rule in this module should be the IAP rule")
		assert.Regexp(t, regexp.MustCompile(`ports\s*=\s*\["22"\]`), block,
			"the IAP rule should open port 22 and nothing else")
	}
}

// TestDenyAllIngressExists checks the defence-in-depth rule is present and, more
// importantly, that it is *lower* precedence than the IAP rule. A deny-all at a
// lower priority number than 1000 would lock the box out entirely.
func TestDenyAllIngressExists(t *testing.T) {
	t.Parallel()

	source := readTerraform(t, filepath.Join(networkDir, "main.tf"))

	require.Contains(t, source, `resource "google_compute_firewall" "deny_all_ingress"`)

	priority := regexp.MustCompile(`(?s)deny_all_ingress.*?priority\s*=\s*(\d+)`).FindStringSubmatch(source)
	require.Len(t, priority, 2, "the deny-all rule must set an explicit priority")
	assert.Equal(t, "65533", priority[1],
		"the deny-all rule must have a higher priority number (lower precedence) than the IAP allow rule at 1000")
}

// TestOsLoginAndHardenedMetadata asserts the third and fourth properties: SSH
// keys come from IAM, project-wide keys cannot be used, the serial console is
// not on by default, and Shielded VM is fully enabled.
func TestOsLoginAndHardenedMetadata(t *testing.T) {
	t.Parallel()

	source := readTerraform(t, filepath.Join(devVMDir, "main.tf"))

	assert.Contains(t, source, `enable-oslogin = "TRUE"`,
		"OS Login must be enabled so SSH keys are managed by IAM rather than metadata")
	assert.Contains(t, source, `block-project-ssh-keys = "TRUE"`,
		"project-wide SSH keys must not be a path onto this box")

	for _, setting := range []string{
		"enable_secure_boot          = true",
		"enable_vtpm                 = true",
		"enable_integrity_monitoring = true",
	} {
		assert.Contains(t, source, setting, "Shielded VM must be fully enabled")
	}

	variables := readTerraform(t, filepath.Join(devVMDir, "variables.tf"))
	serialDefault := regexp.MustCompile(`(?s)variable "enable_serial_console".*?default\s*=\s*(\w+)`).FindStringSubmatch(variables)
	require.Len(t, serialDefault, 2)
	assert.Equal(t, "false", serialDefault[1],
		"the serial console is a break-glass path and must be off by default")
}

// TestDataDiskIsProtected asserts the persistent home disk cannot be destroyed
// by an ordinary destroy, and that the device_name the guest resolves the disk
// through still matches the DATA_DISK_DEVICE the startup script writes. That
// pairing is the one that breaks silently: a renamed device_name leaves
// seed-home.sh looking for a block device that does not exist.
func TestDataDiskIsProtected(t *testing.T) {
	t.Parallel()

	source := readTerraform(t, filepath.Join(devVMDir, "main.tf"))

	assert.Regexp(t, regexp.MustCompile(`(?s)resource "google_compute_disk" "home".*?prevent_destroy\s*=\s*true`), source,
		"the persistent home disk must set prevent_destroy")

	assert.Contains(t, source, `data_disk_device_name = "devhome"`,
		"the attached disk device_name is the other half of the DATA_DISK_DEVICE contract")
	assert.Contains(t, source, `data_disk_device_path = "/dev/disk/by-id/google-${local.data_disk_device_name}"`,
		"the guest device path must be derived from the device_name, not written out twice")
}

// TestServiceAccountIsScoped asserts the VM's own identity stays near-powerless.
// Admin belongs to the human who connects through IAP, not to the box.
func TestServiceAccountIsScoped(t *testing.T) {
	t.Parallel()

	// Comments stripped first: main.tf names roles/editor in prose, explaining why
	// it must never be bound here. A guard that cannot tell the explanation from
	// the mistake would force the explanation to be deleted.
	source := stripComments(readTerraform(t, filepath.Join(devVMDir, "main.tf")))

	assert.Contains(t, source, "roles/logging.logWriter")
	assert.Contains(t, source, "roles/monitoring.metricWriter")

	for _, forbidden := range []string{
		"roles/owner",
		"roles/editor",
		"roles/compute.admin",
		"roles/iam.securityAdmin",
	} {
		assert.NotContains(t, source, forbidden,
			"the instance service account must not hold %s; every process on the box inherits it", forbidden)
	}
}

// TestStartupScriptWritesImageContract checks the metadata startup script hands
// the image's cloud-agnostic boot scripts every key they read. A missing key does
// not fail the boot -- the scripts fall back to defaults -- it just quietly
// applies the wrong configuration.
func TestStartupScriptWritesImageContract(t *testing.T) {
	t.Parallel()

	template := readTerraform(t, filepath.Join(devVMDir, "templates", "startup-script.sh.tftpl"))

	assert.Contains(t, template, "/etc/dev-vm/seed-home.env")
	assert.Contains(t, template, "/etc/dev-vm/idle-shutdown.env")

	for _, key := range []string{
		"TARGET_USER=", "HOME_SEED_DIR=", "FS_LABEL=", "DATA_DISK_DEVICE=",
		"ENABLED=", "IDLE_MINUTES=", "CHECK_INTERVAL_MINUTES=", "LOAD_THRESHOLD=", "IGNORE_CONTAINERS=",
	} {
		assert.Contains(t, template, key, "the startup script must set %s", key)
	}
}

// readTerraform reads a configuration file the tests assert against, failing the
// test rather than skipping if it has moved.
func readTerraform(t *testing.T, path string) string {
	t.Helper()

	content, err := os.ReadFile(path)
	require.NoErrorf(t, err, "cannot read %s; if the layout changed, these guards need updating rather than deleting", path)

	return string(content)
}

// stripComments removes whole-line `#` comments so an assertion about
// configuration is not satisfied -- or defeated -- by prose about it.
func stripComments(source string) string {
	var kept []string
	for _, line := range strings.Split(source, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		kept = append(kept, line)
	}

	return strings.Join(kept, "\n")
}

// firewallBlocks splits a configuration into one string per
// google_compute_firewall resource so each can be checked in isolation.
func firewallBlocks(source string) []string {
	parts := strings.Split(source, `resource "google_compute_firewall"`)
	if len(parts) < 2 {
		return nil
	}

	return parts[1:]
}
