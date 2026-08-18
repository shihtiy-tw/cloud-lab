// Package test contains integration tests for aws/compute/dev-vm.
//
// These create real cloud resources and cost money. Run them against a
// sandbox account only.
//
// What is being tested here is not "did Terraform apply" -- the unit tests cover
// the configuration. It is the four properties the stack exists to hold, verified
// against the live account rather than against the plan:
//
//	1. the instance has no public IP
//	2. its security group has zero ingress rules
//	3. instance metadata requires a session token (IMDSv2)
//	4. the persistent home volume cannot be destroyed by accident
//
// Then it opens a shell the only way that exists -- SSM -- and runs the dotfiles'
// own test suite on the box, because an unreachable VM and a VM with a broken
// home directory are both failures of this stack.
//
// Run with:
//
//	go test -v -timeout 45m ./integration/...
//
// `go test -short` skips everything here.
package test

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/shell"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// aws/tests/helpers is a separate Go module, so its SkipInShortMode cannot be
// imported from here. Same behaviour, three lines.
func skipInShortMode(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}
}

func testRegion() string {
	if region := os.Getenv("AWS_REGION"); region != "" {
		return region
	}
	return "us-east-1"
}

// awsJSON runs an AWS CLI command and unmarshals its JSON output. The CLI is used
// rather than the SDK because these assertions read raw API fields
// (MetadataOptions, IpPermissions) that terratest's helpers do not surface, and
// adding a direct aws-sdk-go dependency to this module for four field reads is a
// worse trade.
func awsJSON(t *testing.T, out interface{}, args ...string) {
	region := testRegion()
	full := append([]string{"--region", region, "--output", "json"}, args...)

	stdout, err := shell.RunCommandAndGetStdOutE(t, shell.Command{
		Command: "aws",
		Args:    full,
	})
	require.NoErrorf(t, err, "aws %s", strings.Join(full, " "))
	require.NoError(t, json.Unmarshal([]byte(stdout), out))
}

type instanceDescription struct {
	Reservations []struct {
		Instances []struct {
			InstanceID       string `json:"InstanceId"`
			PublicIPAddress  string `json:"PublicIpAddress"`
			PrivateIPAddress string `json:"PrivateIpAddress"`
			KeyName          string `json:"KeyName"`
			State            struct {
				Name string `json:"Name"`
			} `json:"State"`
			MetadataOptions struct {
				HTTPEndpoint            string `json:"HttpEndpoint"`
				HTTPTokens              string `json:"HttpTokens"`
				HTTPPutResponseHopLimit int    `json:"HttpPutResponseHopLimit"`
			} `json:"MetadataOptions"`
			NetworkInterfaces []struct {
				Association struct {
					PublicIP string `json:"PublicIp"`
				} `json:"Association"`
			} `json:"NetworkInterfaces"`
			BlockDeviceMappings []struct {
				DeviceName string `json:"DeviceName"`
				EBS        struct {
					VolumeID string `json:"VolumeId"`
				} `json:"Ebs"`
			} `json:"BlockDeviceMappings"`
		} `json:"Instances"`
	} `json:"Reservations"`
}

type securityGroupDescription struct {
	SecurityGroups []struct {
		GroupID             string        `json:"GroupId"`
		IPPermissions       []interface{} `json:"IpPermissions"`
		IPPermissionsEgress []interface{} `json:"IpPermissionsEgress"`
	} `json:"SecurityGroups"`
}

type volumeDescription struct {
	Volumes []struct {
		VolumeID   string `json:"VolumeId"`
		Encrypted  bool   `json:"Encrypted"`
		Size       int    `json:"Size"`
		State      string `json:"State"`
		VolumeType string `json:"VolumeType"`
	} `json:"Volumes"`
}

type instanceInformation struct {
	InstanceInformationList []struct {
		InstanceID   string `json:"InstanceId"`
		PingStatus   string `json:"PingStatus"`
		AgentVersion string `json:"AgentVersion"`
		PlatformName string `json:"PlatformName"`
	} `json:"InstanceInformationList"`
}

type commandInvocation struct {
	Status                string `json:"Status"`
	ResponseCode          int    `json:"ResponseCode"`
	StandardOutputContent string `json:"StandardOutputContent"`
	StandardErrorContent  string `json:"StandardErrorContent"`
}

// TestDevVmApply provisions the stack, asserts on its outputs, and destroys
// it again.
func TestDevVmApply(t *testing.T) {
	skipInShortMode(t)
	t.Parallel()

	region := testRegion()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../infrastructure",
		Vars: map[string]interface{}{
			"project_name": "terratest",
			"environment":  "test",
			"region":       region,
			// A test box only has to boot and answer; the default t3.large is
			// sized for real work.
			"instance_type":    "t3.medium",
			"data_volume_size": 20,
			// The scheduled stop would fight the test if the run straddled it.
			"auto_stop_enabled":     false,
			"idle_shutdown_enabled": false,
		},
		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION": region,
		},
	})

	defer destroyIncludingProtectedVolume(t, terraformOptions, region)
	terraform.InitAndApply(t, terraformOptions)

	instanceID := terraform.Output(t, terraformOptions, "instance_id")
	require.NotEmpty(t, instanceID)

	// The assert-style outputs answer the security questions without an API call.
	// Checking them first means a failure names the property that broke.
	assert.Equal(t, "OK: no public IP assigned", terraform.Output(t, terraformOptions, "public_ip_assertion"))
	assert.Equal(t, "OK: 0 ingress rules", terraform.Output(t, terraformOptions, "ingress_rule_assertion"))
	assert.Equal(t, "OK: IMDSv2 required", terraform.Output(t, terraformOptions, "imdsv2_assertion"))

	startSession := terraform.Output(t, terraformOptions, "ssm_start_session_command")
	assert.Contains(t, startSession, "aws ssm start-session")
	// Without --document-name the session runs unlogged, so the emitted command
	// carrying it is part of the contract, not cosmetic.
	assert.Contains(t, startSession, "--document-name")
	assert.NotContains(t, startSession, "ssh")

	t.Run("no public ip", func(t *testing.T) {
		var described instanceDescription
		awsJSON(t, &described, "ec2", "describe-instances", "--instance-ids", instanceID)
		require.Len(t, described.Reservations, 1)
		require.Len(t, described.Reservations[0].Instances, 1)
		instance := described.Reservations[0].Instances[0]

		assert.Empty(t, instance.PublicIPAddress, "the dev VM must not have a public IP")
		assert.NotEmpty(t, instance.PrivateIPAddress)
		// A public IP can also arrive as an ENI association, which the top-level
		// field does not always show.
		for _, eni := range instance.NetworkInterfaces {
			assert.Empty(t, eni.Association.PublicIP, "no network interface may have a public association")
		}
		// No key pair: there is no SSH key to leak because there is no SSH.
		assert.Empty(t, instance.KeyName)
	})

	t.Run("imdsv2 required", func(t *testing.T) {
		var described instanceDescription
		awsJSON(t, &described, "ec2", "describe-instances", "--instance-ids", instanceID)
		metadata := described.Reservations[0].Instances[0].MetadataOptions

		assert.Equal(t, "required", metadata.HTTPTokens, "IMDSv1 must not be reachable")
		assert.Equal(t, "enabled", metadata.HTTPEndpoint)
		assert.Equal(t, 1, metadata.HTTPPutResponseHopLimit, "a hop limit above 1 lets a container reach the metadata service")
	})

	t.Run("no ingress rules", func(t *testing.T) {
		groupID := terraform.Output(t, terraformOptions, "security_group_id")

		var groups securityGroupDescription
		awsJSON(t, &groups, "ec2", "describe-security-groups", "--group-ids", groupID)
		require.Len(t, groups.SecurityGroups, 1)

		assert.Empty(t, groups.SecurityGroups[0].IPPermissions,
			"the dev VM security group must have no ingress rules at all -- SSM works outbound only")
		assert.NotEmpty(t, groups.SecurityGroups[0].IPPermissionsEgress,
			"egress is the only path the SSM agent has to the service")
	})

	t.Run("volumes encrypted", func(t *testing.T) {
		dataVolumeID := terraform.Output(t, terraformOptions, "data_volume_id")

		var described instanceDescription
		awsJSON(t, &described, "ec2", "describe-instances", "--instance-ids", instanceID)

		// The data volume shows up in the block device mappings too once attached,
		// and describe-volumes rejects a repeated id.
		seen := map[string]bool{dataVolumeID: true}
		volumeIDs := []string{dataVolumeID}
		for _, mapping := range described.Reservations[0].Instances[0].BlockDeviceMappings {
			if id := mapping.EBS.VolumeID; id != "" && !seen[id] {
				seen[id] = true
				volumeIDs = append(volumeIDs, id)
			}
		}

		var volumes volumeDescription
		awsJSON(t, &volumes, append([]string{"ec2", "describe-volumes", "--volume-ids"}, volumeIDs...)...)
		require.NotEmpty(t, volumes.Volumes)

		for _, volume := range volumes.Volumes {
			assert.Truef(t, volume.Encrypted, "volume %s is not encrypted", volume.VolumeID)
		}
	})

	t.Run("dotfiles install verified over ssm", func(t *testing.T) {
		waitForSSMAgent(t, instanceID)

		// runuser, not a bare command: send-command runs as root, and the dotfiles
		// tests resolve symlinks relative to $HOME. As root they would check
		// /root and pass against the wrong home.
		//
		// These are the dotfiles repository's own targets, so this asserts the
		// image contract end to end: the seeded home is present, on the persistent
		// volume, with working symlinks.
		runOnInstance(t, instanceID, "make test-install",
			"runuser -l ubuntu -c 'cd ~/dotfiles && make test-install'")
		runOnInstance(t, instanceID, "make test-symlinks",
			"runuser -l ubuntu -c 'cd ~/dotfiles && make test-symlinks'")

		// The home directory must be the mounted volume, not the image's copy --
		// otherwise nothing survives a rebuild.
		output := runOnInstance(t, instanceID, "home is on the data volume",
			"findmnt --noheadings --output SOURCE,FSTYPE --target /home/ubuntu")
		assert.Contains(t, output, "ext4")

		// The seed marker proves seed-home.sh ran rather than the volume simply
		// happening to contain a home directory.
		runOnInstance(t, instanceID, "seed marker present", "test -f /home/ubuntu/.dev-vm-seeded")
	})
}

// waitForSSMAgent blocks until the instance registers with Session Manager. A
// freshly booted box takes a minute or two, and every SSM-based assertion below
// depends on it -- if this never succeeds, the VM is unreachable and the stack has
// failed its single most important requirement.
func waitForSSMAgent(t *testing.T, instanceID string) {
	retry.DoWithRetry(t, fmt.Sprintf("wait for %s to register with SSM", instanceID), 30, 20*time.Second,
		func() (string, error) {
			var info instanceInformation
			awsJSON(t, &info, "ssm", "describe-instance-information",
				"--filters", fmt.Sprintf("Key=InstanceIds,Values=%s", instanceID))

			for _, entry := range info.InstanceInformationList {
				if entry.InstanceID == instanceID && entry.PingStatus == "Online" {
					return entry.AgentVersion, nil
				}
			}
			return "", fmt.Errorf("instance %s has not reported Online to SSM yet", instanceID)
		})
}

// runOnInstance executes a shell command on the box through SSM and fails the
// test unless it exits zero. This is also the proof that the connectivity model
// works: no inbound rule, no public IP, and still a usable shell.
func runOnInstance(t *testing.T, instanceID, description, command string) string {
	parameters, err := json.Marshal(map[string][]string{
		"commands":         {command},
		"executionTimeout": {"1800"},
	})
	require.NoError(t, err)

	var sent struct {
		Command struct {
			CommandID string `json:"CommandId"`
		} `json:"Command"`
	}
	awsJSON(t, &sent, "ssm", "send-command",
		"--instance-ids", instanceID,
		"--document-name", "AWS-RunShellScript",
		"--comment", description,
		"--parameters", string(parameters))
	require.NotEmpty(t, sent.Command.CommandID)

	result := retry.DoWithRetry(t, fmt.Sprintf("wait for %q on %s", description, instanceID), 60, 15*time.Second,
		func() (string, error) {
			var invocation commandInvocation
			awsJSON(t, &invocation, "ssm", "get-command-invocation",
				"--command-id", sent.Command.CommandID,
				"--instance-id", instanceID)

			switch invocation.Status {
			case "Pending", "InProgress", "Delayed":
				return "", fmt.Errorf("%s is %s", description, invocation.Status)
			case "Success":
				return invocation.StandardOutputContent, nil
			default:
				// A non-retryable failure: stop retrying and surface the box's own
				// stderr, which is the only diagnostic available on a VM with no SSH.
				return "", retry.FatalError{Underlying: fmt.Errorf(
					"%s failed with status %s (exit %d)\nstdout:\n%s\nstderr:\n%s",
					description, invocation.Status, invocation.ResponseCode,
					invocation.StandardOutputContent, invocation.StandardErrorContent)}
			}
		})

	return result
}

// destroyIncludingProtectedVolume cleans up a stack whose home volume carries
// lifecycle.prevent_destroy.
//
// That protection is the point of the volume, so a plain `terraform destroy`
// fails -- which this asserts, since a destroy that succeeded would mean the
// protection had been lost. Cleanup then does explicitly what a human retiring
// the box would do: drop the volume from state, destroy the rest, and delete the
// volume by hand.
func destroyIncludingProtectedVolume(t *testing.T, terraformOptions *terraform.Options, region string) {
	if os.Getenv("SKIP_DESTROY") == "true" {
		t.Log("SKIP_DESTROY is set, leaving the stack in place")
		return
	}

	_, err := terraform.DestroyE(t, terraformOptions)
	assert.Error(t, err, "destroy must fail while the home volume is protected by prevent_destroy")
	if err != nil {
		assert.Contains(t, err.Error(), "prevent_destroy")
	}

	volumeID, outputErr := terraform.OutputE(t, terraformOptions, "data_volume_id")

	terraform.RunTerraformCommand(t, terraformOptions, "state", "rm", "aws_ebs_volume.home")
	terraform.Destroy(t, terraformOptions)

	if outputErr == nil && volumeID != "" {
		shell.RunCommand(t, shell.Command{
			Command: "aws",
			Args:    []string{"--region", region, "ec2", "delete-volume", "--volume-id", volumeID},
		})
	}
}
