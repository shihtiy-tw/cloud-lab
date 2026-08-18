// Package test contains integration tests for azure/compute/dev-vm.
//
// These create real cloud resources and cost money. Run them against a sandbox
// subscription only:
//
//	go test -v -timeout 60m ./integration/...          # runs them
//	go test -short ./...                               # skips them
//
// What they are for: the unit tests assert the security properties against the
// configuration, which catches a regression as it is written but proves nothing
// about Azure's behaviour. These assert the same properties against the deployed
// resources, and then check that the image's own contract still holds by running
// the dotfiles test targets on the box -- over `az vm run-command`, because there
// is no SSH path from here and that is the point.
//
// Prerequisites:
//   - az CLI logged in to a sandbox subscription (ARM_SUBSCRIPTION_ID set)
//   - a dev-vm gallery image published by shared/packer, or DEV_VM_IMAGE_ID
//   - an SSH public key at ~/.ssh/id_ed25519.pub, or DEV_VM_SSH_PUBLIC_KEY
package test

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestDevVmApply provisions the stack, asserts the security properties on the
// live resources, exercises the image contract on the VM, and tears everything
// down again.
func TestDevVmApply(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in -short mode: it creates real Azure resources")
	}

	t.Parallel()

	sshPublicKey := resolveSSHPublicKey(t)
	resourceGroupName := fmt.Sprintf("terratest-devvm-%s", strings.ToLower(random.UniqueId()))

	variables := map[string]interface{}{
		"project_name": "terratest",
		"environment":  "test",
		// A dedicated resource group, created and destroyed by the test, so a
		// failed run cannot leave debris in a shared one.
		"resource_group_name":   resourceGroupName,
		"create_resource_group": true,
		"location":              envOrDefault("DEV_VM_LOCATION", "eastus"),
		"ssh_public_keys":       []string{sshPublicKey},
		// Developer SKU: free, and provisions in a couple of minutes rather than
		// the ten a Basic/Standard deployment takes.
		"bastion_sku": "Developer",
		// Nightly stops would be noise on a VM that lives for 20 minutes.
		"auto_stop_enabled":     false,
		"idle_shutdown_enabled": false,
	}

	if imageID := os.Getenv("DEV_VM_IMAGE_ID"); imageID != "" {
		variables["image_id"] = imageID
	}

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../infrastructure",
		Vars:         variables,
		NoColor:      true,
	})

	defer cleanup(t, terraformOptions, resourceGroupName)
	terraform.InitAndApply(t, terraformOptions)

	vmName := terraform.Output(t, terraformOptions, "vm_name")
	require.NotEmpty(t, vmName)

	t.Run("NicHasNoPublicIp", func(t *testing.T) {
		// From the outputs first...
		assert.Equal(t, "false", terraform.Output(t, terraformOptions, "nic_has_public_ip"))
		assert.Empty(t, terraform.OutputList(t, terraformOptions, "nic_public_ip_ids"))

		// ...and then from Azure, because an output only proves what Terraform
		// believes. `az vm list-ip-addresses` reports every public address
		// attached to the VM, so an empty result is the property itself.
		addresses := az(t,
			"vm", "list-ip-addresses",
			"--name", vmName,
			"--resource-group", terraform.Output(t, terraformOptions, "resource_group_name"),
			"--query", "[0].virtualMachine.network.publicIpAddresses",
			"--output", "json",
		)
		var publicIPs []interface{}
		require.NoError(t, json.Unmarshal([]byte(addresses), &publicIPs))
		assert.Empty(t, publicIPs, "the dev VM must have no public IP; it is reachable only through Bastion")
	})

	t.Run("NoInternetInboundNsgRule", func(t *testing.T) {
		// OutputJson rather than OutputMap: the network output includes
		// bastion_subnet_id, which is null for the Developer SKU, and OutputMap
		// cannot represent a null.
		var network map[string]interface{}
		require.NoError(t, json.Unmarshal([]byte(terraform.OutputJson(t, terraformOptions, "network")), &network))

		nsgID, ok := network["network_security_group_id"].(string)
		require.True(t, ok, "network output must carry the NSG id")
		require.NotEmpty(t, nsgID)

		rules := az(t,
			"network", "nsg", "show",
			"--ids", nsgID,
			"--query", "securityRules[?direction=='Inbound' && access=='Allow'].{name: name, source: sourceAddressPrefix, sources: sourceAddressPrefixes, port: destinationPortRange}",
			"--output", "json",
		)

		var inbound []struct {
			Name    string   `json:"name"`
			Source  string   `json:"source"`
			Sources []string `json:"sources"`
			Port    string   `json:"port"`
		}
		require.NoError(t, json.Unmarshal([]byte(rules), &inbound))

		internetWide := map[string]bool{"Internet": true, "*": true, "0.0.0.0/0": true, "::/0": true, "AzureCloud": true}
		for _, rule := range inbound {
			assert.False(t, internetWide[rule.Source],
				"inbound Allow rule %q must not be sourced from %q", rule.Name, rule.Source)
			for _, source := range rule.Sources {
				assert.False(t, internetWide[source],
					"inbound Allow rule %q must not be sourced from %q", rule.Name, source)
			}
		}
	})

	t.Run("PasswordAuthenticationDisabled", func(t *testing.T) {
		assert.Equal(t, "true", terraform.Output(t, terraformOptions, "password_authentication_disabled"))

		disabled := az(t,
			"vm", "show",
			"--name", vmName,
			"--resource-group", terraform.Output(t, terraformOptions, "resource_group_name"),
			"--query", "osProfile.linuxConfiguration.disablePasswordAuthentication",
			"--output", "tsv",
		)
		assert.Equal(t, "true", strings.TrimSpace(disabled),
			"sshd on the VM must refuse password authentication")
	})

	t.Run("PersistentHomeDiskAttachedAtLunZero", func(t *testing.T) {
		lun := az(t,
			"vm", "show",
			"--name", vmName,
			"--resource-group", terraform.Output(t, terraformOptions, "resource_group_name"),
			"--query", "storageProfile.dataDisks[0].lun",
			"--output", "tsv",
		)
		// /dev/disk/azure/scsi1/lun0 in the VM's seed-home.env resolves through
		// this number. A non-zero lun here means the home directory silently came
		// from the image instead of the disk.
		assert.Equal(t, "0", strings.TrimSpace(lun))

		mounted := runOnVM(t, terraformOptions, vmName,
			"findmnt --noheadings --output SOURCE,TARGET,FSTYPE --target /home/ubuntu")
		assert.Contains(t, mounted, "/home/ubuntu",
			"the persistent disk must be mounted at the user's home directory")
	})

	// The image contract. shared/bootstrap/install.sh baked the dotfiles in and
	// seed-home.sh restored them onto the persistent disk; these are the dotfiles'
	// own tests, so they check the thing a developer actually cares about.
	t.Run("DotfilesInstallTests", func(t *testing.T) {
		output := runOnVM(t, terraformOptions, vmName,
			"sudo -iu ubuntu bash -lc 'cd ~/dotfiles && make test-install'")
		assert.NotContains(t, strings.ToLower(output), "error",
			"make test-install must pass on the provisioned VM:\n%s", output)
	})

	t.Run("DotfilesSymlinkTests", func(t *testing.T) {
		output := runOnVM(t, terraformOptions, vmName,
			"sudo -iu ubuntu bash -lc 'cd ~/dotfiles && make test-symlinks'")
		assert.NotContains(t, strings.ToLower(output), "error",
			"make test-symlinks must pass on the provisioned VM:\n%s", output)
	})

	t.Run("BootDiagnosticsEnabled", func(t *testing.T) {
		// Break-glass has to be verified while things work. With no SSH from the
		// internet, a broken Bastion plus disabled boot diagnostics is a VM nobody
		// can reach at all.
		enabled := az(t,
			"vm", "show",
			"--name", vmName,
			"--resource-group", terraform.Output(t, terraformOptions, "resource_group_name"),
			"--query", "diagnosticsProfile.bootDiagnostics.enabled",
			"--output", "tsv",
		)
		assert.Equal(t, "true", strings.TrimSpace(enabled))
	})
}

// runOnVM executes a shell command on the VM through the Azure control plane.
//
// Not over SSH, deliberately: there is no SSH route from a test runner to this
// VM, and `az vm run-command` is the same brokered, RBAC-gated path the design
// relies on everywhere else. It needs no network reachability at all, which also
// makes it the tool of choice for debugging a Bastion problem.
func runOnVM(t *testing.T, terraformOptions *terraform.Options, vmName string, script string) string {
	t.Helper()

	return az(t,
		"vm", "run-command", "invoke",
		"--name", vmName,
		"--resource-group", terraform.Output(t, terraformOptions, "resource_group_name"),
		"--command-id", "RunShellScript",
		"--scripts", script,
		"--query", "value[0].message",
		"--output", "tsv",
	)
}

func az(t *testing.T, args ...string) string {
	t.Helper()

	return shell.RunCommandAndGetStdOut(t, shell.Command{
		Command: "az",
		Args:    args,
	})
}

// cleanup tears the stack down. The home disk carries prevent_destroy, which is
// exactly what it is there for and also what makes `terraform destroy` refuse to
// run, so the disk is dropped from state first and the resource group is deleted
// afterwards to catch it. Do not "fix" this by removing prevent_destroy: the
// protection is a deliverable of this stack, and a test is the one place where
// working around it is legitimate.
func cleanup(t *testing.T, terraformOptions *terraform.Options, resourceGroupName string) {
	t.Helper()

	if _, err := terraform.RunTerraformCommandE(t, terraformOptions,
		"state", "rm", "azurerm_managed_disk.home"); err != nil {
		t.Logf("could not drop the home disk from state (it may never have been created): %v", err)
	}

	if _, err := terraform.DestroyE(t, terraformOptions); err != nil {
		t.Logf("terraform destroy reported an error; falling back to deleting the resource group: %v", err)
	}

	// Sweeps up the orphaned disk and anything destroy could not reach. --no-wait
	// because the test has nothing left to learn from watching it.
	if _, err := shell.RunCommandAndGetStdOutE(t, shell.Command{
		Command: "az",
		Args:    []string{"group", "delete", "--name", resourceGroupName, "--yes", "--no-wait"},
	}); err != nil {
		t.Logf("could not delete resource group %s; check for leftovers: %v", resourceGroupName, err)
	}
}

// resolveSSHPublicKey finds the key to provision. The VM has no password, so a
// run with no key would fail the stack's own plan-time precondition -- skip with
// an explanation instead.
func resolveSSHPublicKey(t *testing.T) string {
	t.Helper()

	if key := os.Getenv("DEV_VM_SSH_PUBLIC_KEY"); key != "" {
		return strings.TrimSpace(key)
	}

	home, err := os.UserHomeDir()
	require.NoError(t, err)

	for _, name := range []string{"id_ed25519.pub", "id_rsa.pub"} {
		content, err := os.ReadFile(filepath.Join(home, ".ssh", name))
		if err == nil {
			return strings.TrimSpace(string(content))
		}
	}

	t.Skip("no SSH public key found: set DEV_VM_SSH_PUBLIC_KEY or create ~/.ssh/id_ed25519.pub")

	return ""
}

func envOrDefault(name string, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}

	return fallback
}
