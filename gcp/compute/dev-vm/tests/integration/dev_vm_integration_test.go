// Package test contains integration tests for gcp/compute/dev-vm.
//
// These create real cloud resources and cost money. Run them against a
// sandbox project only:
//
//	export GCP_PROJECT_ID=my-sandbox-project
//	export GCP_DEVELOPER_PRINCIPAL=user:you@example.com
//	go test -v -timeout 60m ./integration/...
//
// `go test -short ./...` skips everything here, which is what CI runs.
//
// Two things make this suite unusual, both consequences of the design under
// test:
//
//  1. There is no public endpoint to connect to, so every on-box assertion goes
//     through `gcloud compute ssh --tunnel-through-iap`. That also makes the
//     tunnel itself part of what is being tested: if IAP or OS Login is
//     misconfigured, these tests fail at the connection, which is the correct
//     outcome.
//  2. The persistent home disk sets prevent_destroy, so a plain
//     terraform.Destroy cannot clean up. See cleanup() for how that is handled
//     and why it has to delete the disk out of band.
package test

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const iapRangeCIDR = "35.235.240.0/20"

// TestDevVmApply provisions the stack, asserts the security properties hold on
// the live resources, exercises the dotfiles' own test targets over the IAP
// tunnel, and tears everything down again.
func TestDevVmApply(t *testing.T) {
	t.Parallel()

	if testing.Short() {
		t.Skip("skipping integration test in short mode: this provisions real, billable GCP resources")
	}

	projectID := requireEnv(t, "GCP_PROJECT_ID")

	// Without a principal there is nothing to grant IAP access to, and the SSH
	// stages below cannot run. Failing here beats failing 10 minutes into an apply.
	developer := requireEnv(t, "GCP_DEVELOPER_PRINCIPAL")

	region := envOrDefault("GCP_REGION", "us-central1")
	zone := envOrDefault("GCP_ZONE", region+"-a")

	// A unique name per run keeps two concurrent runs from fighting over the same
	// zonal disk, which is the one resource here that cannot be recreated freely.
	uniqueID := strings.ToLower(random.UniqueId())

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../infrastructure",
		Vars: map[string]interface{}{
			"project_name":         fmt.Sprintf("tt%s", uniqueID),
			"environment":          "test",
			"project_id":           projectID,
			"region":               region,
			"zone":                 zone,
			"developer_principals": []string{developer},

			// Smallest shape that still boots the image; the dotfiles test targets
			// do not compile anything heavy.
			"machine_type":   "e2-standard-2",
			"data_disk_size": 10,

			// Both auto-stop mechanisms off for the duration of the test. An idle
			// timer that fires between two SSH stages produces a confusing failure
			// that looks like a broken tunnel.
			"idle_shutdown_enabled": false,
			"auto_stop_enabled":     false,
		},
	})

	defer cleanup(t, terraformOptions, projectID, zone)
	terraform.InitAndApply(t, terraformOptions)

	instanceName := terraform.Output(t, terraformOptions, "instance_name")
	require.NotEmpty(t, instanceName)

	t.Run("NoExternalIP", func(t *testing.T) {
		// The requirement, asserted two ways: from Terraform's own view of the
		// resource, and from the API, because the second would catch an external IP
		// attached out of band.
		assert.Equal(t, "false", terraform.Output(t, terraformOptions, "has_external_ip"),
			"the dev VM must have no external IP; an access_config block was added")
		assert.Empty(t, terraform.OutputList(t, terraformOptions, "external_ip_addresses"),
			"the dev VM must have no external addresses at all")

		described := gcloud(t, "compute", "instances", "describe", instanceName,
			"--zone", zone, "--project", projectID,
			"--format", "value(networkInterfaces[0].accessConfigs[0].natIP)")
		assert.Empty(t, strings.TrimSpace(described),
			"the API reports an external IP on an instance that must not have one")
	})

	t.Run("SshIngressIsIapOnly", func(t *testing.T) {
		ranges := terraform.OutputList(t, terraformOptions, "iap_firewall_source_ranges")
		assert.Equal(t, []string{iapRangeCIDR}, ranges,
			"port 22 must be reachable from the IAP forwarding range and nothing else")

		// Anything in the project that opens 22 wider than IAP defeats this stack,
		// even if it is not part of it.
		firewalls := gcloud(t, "compute", "firewall-rules", "list",
			"--project", projectID,
			"--filter", fmt.Sprintf("network~%s AND allowed[].ports~22", terraform.Output(t, terraformOptions, "network_name")),
			"--format", "value(sourceRanges.list())")
		for _, line := range nonEmptyLines(firewalls) {
			assert.NotContains(t, line, "0.0.0.0/0",
				"a firewall rule in this VPC opens port 22 to the internet")
		}
	})

	t.Run("OsLoginAndShieldedVm", func(t *testing.T) {
		assert.Equal(t, "true", terraform.Output(t, terraformOptions, "oslogin_enabled"),
			"OS Login must be on so SSH keys come from IAM, not metadata")
		assert.Equal(t, "false", terraform.Output(t, terraformOptions, "serial_console_enabled"),
			"the serial console must stay off outside an active recovery")

		oslogin := gcloud(t, "compute", "instances", "describe", instanceName,
			"--zone", zone, "--project", projectID,
			"--format", "value(metadata.items.filter(\"key:enable-oslogin\").extract(\"value\").flatten())")
		assert.Equal(t, "TRUE", strings.TrimSpace(oslogin))

		shielded := terraform.OutputMap(t, terraformOptions, "shielded_vm")
		assert.Equal(t, "true", shielded["secure_boot"])
		assert.Equal(t, "true", shielded["vtpm"])
		assert.Equal(t, "true", shielded["integrity_monitoring"])
	})

	t.Run("PersistentDiskAttachedAsDevhome", func(t *testing.T) {
		assert.NotEmpty(t, terraform.Output(t, terraformOptions, "data_disk_id"))
		assert.Equal(t, "/dev/disk/by-id/google-devhome",
			terraform.Output(t, terraformOptions, "data_disk_device_path"),
			"the guest device path must match the attached disk's device_name")

		deviceName := gcloud(t, "compute", "instances", "describe", instanceName,
			"--zone", zone, "--project", projectID,
			"--format", "value(disks[1].deviceName)")
		assert.Equal(t, "devhome", strings.TrimSpace(deviceName),
			"seed-home.sh resolves the disk through /dev/disk/by-id/google-devhome; a different device_name breaks first boot")
	})

	// Everything below needs the box up and the tunnel working. Give the image
	// time to finish first boot: the startup script re-runs the home seeding, and
	// on a fresh disk that is an rsync of the whole baked home.
	waitForIapSsh(t, projectID, zone, instanceName)

	t.Run("HomeSeededOntoPersistentDisk", func(t *testing.T) {
		// The seeding contract, verified from the guest: home is the mounted data
		// disk, it carries the marker seed-home.sh writes, and the dotfiles the
		// image baked survived being mounted over.
		mount := ssh(t, projectID, zone, instanceName,
			"findmnt --noheadings --output SOURCE --target \"$HOME\"")
		assert.NotEmpty(t, strings.TrimSpace(mount), "home should be a separate mounted filesystem")

		marker := ssh(t, projectID, zone, instanceName, "test -f \"$HOME/.dev-vm-seeded\" && echo seeded")
		assert.Contains(t, marker, "seeded", "seed-home.sh did not mark the disk as seeded")

		label := ssh(t, projectID, zone, instanceName,
			"lsblk --noheadings --output LABEL \"$(findmnt --noheadings --output SOURCE --target \"$HOME\")\"")
		assert.Contains(t, label, "devhome", "the home filesystem should carry the devhome label")

		dotfiles := ssh(t, projectID, zone, instanceName, "test -d \"$HOME/dotfiles\" && echo present")
		assert.Contains(t, dotfiles, "present", "the baked ~/dotfiles did not survive the disk mount")
	})

	t.Run("BootScriptConfigurationWasDelivered", func(t *testing.T) {
		seedEnv := ssh(t, projectID, zone, instanceName, "cat /etc/dev-vm/seed-home.env")
		assert.Contains(t, seedEnv, "DATA_DISK_DEVICE=/dev/disk/by-id/google-devhome")
		assert.Contains(t, seedEnv, "FS_LABEL=devhome")

		idleEnv := ssh(t, projectID, zone, instanceName, "cat /etc/dev-vm/idle-shutdown.env")
		assert.Contains(t, idleEnv, "CHECK_INTERVAL_MINUTES=5",
			"must match OnUnitActiveSec in dev-vm-idle-shutdown.timer")
		assert.Contains(t, idleEnv, "ENABLED=false",
			"this test disables the idle timer; the startup script should have written that through")
	})

	t.Run("DotfilesSelfTest", func(t *testing.T) {
		// The dotfiles repo ships its own verification, and it is a better check of
		// "is this image usable?" than anything reimplemented here. Run it where it
		// actually matters: on the box, over the tunnel, as the login user.
		installOutput := ssh(t, projectID, zone, instanceName, "cd \"$HOME/dotfiles\" && make test-install")
		assert.NotContains(t, strings.ToLower(installOutput), "failed",
			"dotfiles `make test-install` reported failures:\n%s", installOutput)

		symlinkOutput := ssh(t, projectID, zone, instanceName, "cd \"$HOME/dotfiles\" && make test-symlinks")
		assert.NotContains(t, strings.ToLower(symlinkOutput), "failed",
			"dotfiles `make test-symlinks` reported failures:\n%s", symlinkOutput)
	})

	t.Run("PersistentDiskSurvivesInstanceReplacement", func(t *testing.T) {
		// The reason the disk exists. Write a file, recreate the instance, and check
		// the file is still there -- which is the property `prevent_destroy` and the
		// seeding marker together are supposed to guarantee.
		ssh(t, projectID, zone, instanceName, "echo persisted > \"$HOME/.terratest-witness\"")

		// -replace rather than the deprecated `terraform taint`, and note it names
		// only the instance: the disk is a separate resource and must not be
		// replaced with it.
		terraform.RunTerraformCommand(t, terraformOptions,
			terraform.FormatArgs(terraformOptions, "apply", "-input=false", "-auto-approve",
				"-replace=google_compute_instance.dev_vm")...)

		waitForIapSsh(t, projectID, zone, instanceName)

		witness := ssh(t, projectID, zone, instanceName, "cat \"$HOME/.terratest-witness\"")
		assert.Contains(t, witness, "persisted",
			"the persistent home disk lost data across an instance replacement")
	})
}

// waitForIapSsh blocks until the tunnel accepts a command. First boot has to
// finish the startup script and the home seeding before a login lands in the
// right home directory, and IAP itself returns errors for a few seconds after the
// instance reports RUNNING.
func waitForIapSsh(t *testing.T, projectID, zone, instanceName string) {
	t.Helper()

	retry.DoWithRetry(t, "wait for IAP SSH", 40, 15*time.Second, func() (string, error) {
		out, err := shell.RunCommandAndGetOutputE(t, sshCommand(projectID, zone, instanceName,
			"systemctl is-active dev-vm-seed-home.service || true"))
		if err != nil {
			return "", err
		}
		if !strings.Contains(out, "active") {
			return "", fmt.Errorf("home seeding has not completed yet: %s", out)
		}

		return out, nil
	})
}

// ssh runs one command on the box through the IAP tunnel. Note the absence of a
// host or an IP anywhere in here: there is nothing to connect to directly, which
// is the point.
func ssh(t *testing.T, projectID, zone, instanceName, remoteCommand string) string {
	t.Helper()

	return shell.RunCommandAndGetOutput(t, sshCommand(projectID, zone, instanceName, remoteCommand))
}

func sshCommand(projectID, zone, instanceName, remoteCommand string) shell.Command {
	return shell.Command{
		Command: "gcloud",
		Args: []string{
			"compute", "ssh", instanceName,
			"--project", projectID,
			"--zone", zone,
			"--tunnel-through-iap",
			// Strict host key checking against a rebuilt VM fails on a changed key;
			// the tunnel is what authenticates the endpoint here.
			"--strict-host-key-checking=no",
			"--command", remoteCommand,
		},
	}
}

func gcloud(t *testing.T, args ...string) string {
	t.Helper()

	return shell.RunCommandAndGetOutput(t, shell.Command{Command: "gcloud", Args: args})
}

// cleanup tears the stack down. It cannot be a plain terraform.Destroy: the
// persistent home disk sets prevent_destroy, which makes destroy refuse to run
// at all rather than skipping that one resource.
//
// So the disk is dropped from state first -- which removes Terraform's
// protection without touching the cloud resource -- then everything else is
// destroyed, then the now-unmanaged disk is deleted directly. That last step is
// what stops a test run from leaving a billable orphan behind, and it is only
// acceptable because this disk is a fixture. Never run this shape against a disk
// someone works on.
func cleanup(t *testing.T, terraformOptions *terraform.Options, projectID, zone string) {
	diskName, err := terraform.OutputE(t, terraformOptions, "data_disk_name")
	if err != nil {
		t.Logf("could not read the data disk name; check for an orphaned disk by hand: %v", err)
	}

	if _, err := terraform.RunTerraformCommandE(t, terraformOptions, "state", "rm", "google_compute_disk.home"); err != nil {
		t.Logf("could not remove the data disk from state; destroy may fail: %v", err)
	}

	terraform.Destroy(t, terraformOptions)

	if diskName != "" {
		if _, err := shell.RunCommandAndGetOutputE(t, shell.Command{
			Command: "gcloud",
			Args:    []string{"compute", "disks", "delete", diskName, "--zone", zone, "--project", projectID, "--quiet"},
		}); err != nil {
			t.Errorf("leaked test disk %s in %s: delete it by hand, it bills until you do: %v", diskName, zone, err)
		}
	}
}

func requireEnv(t *testing.T, name string) string {
	t.Helper()

	value := os.Getenv(name)
	require.NotEmptyf(t, value, "%s must be set to run the integration tests", name)

	return value
}

func envOrDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}

	return fallback
}

func nonEmptyLines(output string) []string {
	var lines []string
	for _, line := range strings.Split(output, "\n") {
		if strings.TrimSpace(line) != "" {
			lines = append(lines, line)
		}
	}

	return lines
}
