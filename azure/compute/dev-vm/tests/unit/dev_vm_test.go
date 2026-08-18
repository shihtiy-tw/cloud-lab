// Package test contains Terratest checks for azure/compute/dev-vm.
//
// Everything in this file runs with no Azure credentials and creates nothing:
// terraform init -backend=false plus validate, and a set of source-level
// assertions on the security properties the stack exists to guarantee.
//
// The source-level tests are deliberate. The properties that matter here are
// absences -- no public IP on the NIC, no internet-sourced inbound rule, no
// admin_password -- and an absence cannot be asserted from an output without a
// live subscription. Asserting them against the configuration catches the
// regression at the moment someone writes it, in a test that costs nothing to run.
//
// Comments are stripped before every assertion. The configuration explains at
// length why there is no public_ip_address_id on the NIC, and a test that reads
// prose as code would fail on the explanation.
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
	infrastructureDir = "../../infrastructure"
	networkModuleDir  = "../../../../shared/modules/network"
)

// TestDevVmValidate initialises and validates the stack without creating
// anything, so it is safe to run without cloud credentials.
func TestDevVmValidate(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: infrastructureDir,
		Vars: map[string]interface{}{
			"project_name": "terratest",
			"environment":  "test",
		},
		NoColor: true,
	})

	terraform.Init(t, terraformOptions)
	terraform.Validate(t, terraformOptions)
}

// TestNetworkModuleValidate validates the network module on its own. It has one
// consumer today, but a module that cannot be validated standalone is a module
// nobody can safely refactor.
func TestNetworkModuleValidate(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: networkModuleDir,
		NoColor:      true,
	})

	terraform.Init(t, terraformOptions)
	terraform.Validate(t, terraformOptions)
}

// TestNicHasNoPublicIP is the headline requirement -- "do not use ssh to open to
// public network" -- and a public IP on the NIC would undo it in one line.
//
// The NAT Gateway's public IP, over in the network module, is a different thing
// and is required, so this looks only at the network interface.
func TestNicHasNoPublicIP(t *testing.T) {
	t.Parallel()

	nic := extractBlock(t, code(readFile(t, infrastructureDir, "main.tf")), "azurerm_network_interface", "")

	assert.NotContains(t, nic, "public_ip_address_id",
		"the dev VM's NIC must have no public IP: it is reachable only through Azure Bastion")
	assert.Contains(t, nic, "subnet_id",
		"the NIC must still be attached to the workload subnet")
}

// TestOnlyBastionHasAPublicIP guards the other direction: a public IP resource in
// this stack that is not Bastion's means someone intended to attach one to the VM.
func TestOnlyBastionHasAPublicIP(t *testing.T) {
	t.Parallel()

	config := code(readFile(t, infrastructureDir, "main.tf"))

	for _, match := range regexp.MustCompile(`resource\s+"azurerm_public_ip"\s+"(\w+)"`).FindAllStringSubmatch(config, -1) {
		assert.Equal(t, "bastion", match[1],
			"the only public IP in this stack may be Bastion's; found one named %q", match[1])
	}
}

// TestNoInternetInboundRules asserts the NSG never allows the internet in. The
// module enforces this with a variable validation too; this is the belt to that
// pair of braces.
func TestNoInternetInboundRules(t *testing.T) {
	t.Parallel()

	config := code(readFile(t, networkModuleDir, "main.tf"))

	require.Contains(t, config, `resource "azurerm_network_security_rule" "deny_all_inbound"`,
		"the NSG must state deny-all-inbound explicitly rather than rely on Azure's invisible default")

	allowRule := extractBlock(t, config, "azurerm_network_security_rule", "allow_bastion_ssh_inbound")
	assertMatches(t, allowRule, `source_address_prefix\s*=\s*var\.bastion_ssh_source_address_prefix`,
		"the only inbound Allow rule must take its source from the validated variable")
	assertMatches(t, allowRule, `destination_port_range\s*=\s*"22"`,
		"the only inbound Allow rule must be scoped to SSH")

	for _, forbidden := range []string{`"Internet"`, `"0\.0\.0\.0/0"`, `"\*"`, `"AzureCloud"`} {
		assertDoesNotMatch(t, allowRule, `source_address_prefix\s*=\s*`+forbidden,
			"inbound SSH must never be allowed from "+forbidden)
	}

	variables := code(readFile(t, networkModuleDir, "variables.tf"))
	assert.Contains(t, variables, "bastion_ssh_source_address_prefix must not be an internet-wide scope",
		"the variable must reject internet-wide sources itself, not merely document that it should not be given one")
}

// TestPasswordAuthenticationDisabled -- a password is the only credential on a VM
// that a guessing attack can ever use, and the one most likely to be committed.
func TestPasswordAuthenticationDisabled(t *testing.T) {
	t.Parallel()

	config := code(readFile(t, infrastructureDir, "main.tf"))

	assertMatches(t, config, `disable_password_authentication\s*=\s*true`, "password authentication must be disabled")
	assert.NotContains(t, config, "admin_password",
		"the VM must have no password; SSH keys tunnelled over Bastion are the only credential")
}

// TestDiskProperties covers encryption in the host and the home disk's
// prevent_destroy, which is what makes `make destroy` a cost decision rather than
// a data-loss event.
func TestDiskProperties(t *testing.T) {
	t.Parallel()

	config := code(readFile(t, infrastructureDir, "main.tf"))

	assertMatches(t, config, `encryption_at_host_enabled\s*=\s*var\.encryption_at_host_enabled`,
		"encryption at host must be wired to a variable, defaulting on")

	variables := code(readFile(t, infrastructureDir, "variables.tf"))
	assertMatches(t, variables, `variable "encryption_at_host_enabled"[\s\S]*?default\s*=\s*true`,
		"encryption at host must default to true")

	homeDisk := extractBlock(t, config, "azurerm_managed_disk", "home")
	assertMatches(t, homeDisk, `prevent_destroy\s*=\s*true`,
		"the persistent home disk must survive a destroy of the rest of the stack")
	assertMatches(t, homeDisk, `storage_account_type\s*=\s*var\.data_disk_storage_account_type`,
		"the home disk's type must be explicit; platform encryption at rest comes with it")
}

// TestDataDiskLunMatchesSeedDevice is the test that earns its keep. The lun on the
// attachment and the DATA_DISK_DEVICE path in cloud-init are one fact written in
// two files, and when they disagree the VM boots perfectly well while quietly
// serving the image's copy of the home directory instead of the persistent disk.
func TestDataDiskLunMatchesSeedDevice(t *testing.T) {
	t.Parallel()

	config := code(readFile(t, infrastructureDir, "main.tf"))
	template := readFile(t, infrastructureDir, filepath.Join("templates", "cloud-init.yaml.tftpl"))

	assertMatches(t, config, `data_disk_lun\s*=\s*0`,
		"lun 0 is what /dev/disk/azure/scsi1/lun0 refers to")
	assertMatches(t, config, `data_disk_device\s*=\s*"/dev/disk/azure/scsi1/lun\$\{local\.data_disk_lun\}"`,
		"the device path must be derived from the lun rather than written out twice")
	assertMatches(t, config, `lun\s*=\s*local\.data_disk_lun`,
		"the attachment must use the same lun the device path was derived from")
	assert.Contains(t, template, "DATA_DISK_DEVICE=${data_disk_device}",
		"cloud-init must pass the device path through to seed-home.env")
	assert.Contains(t, template, "TARGET_USER=${target_user}",
		"cloud-init must pass the admin user through as TARGET_USER, or the seeded home belongs to nobody")
	assert.Contains(t, template, "CHECK_INTERVAL_MINUTES=${check_interval_minutes}",
		"the idle-shutdown interval must be passed through so it can match the timer on the image")
}

// TestImageVersionIsPinned -- "latest" turns every Packer build into a VM
// replacement at whatever moment the next apply happens to run.
func TestImageVersionIsPinned(t *testing.T) {
	t.Parallel()

	variables := code(readFile(t, infrastructureDir, "variables.tf"))

	assertMatches(t, variables, `condition\s*=\s*var\.image_version\s*!=\s*"latest"`,
		"image_version must be prevented from being set to latest")
}

// TestIdentityIsNotOverPrivileged -- anyone with a shell on the VM can mint tokens
// for its managed identity from IMDS, so Contributor there would make a dev box
// compromise a subscription compromise.
func TestIdentityIsNotOverPrivileged(t *testing.T) {
	t.Parallel()

	variables := code(readFile(t, infrastructureDir, "variables.tf"))

	assertMatches(t, variables, `!contains\(\["Owner", "Contributor", "User Access Administrator"\], assignment\.role_definition_name\)`,
		"the VM identity must be blocked from holding subscription-admin roles")

	config := code(readFile(t, infrastructureDir, "main.tf"))
	assert.Contains(t, config, `resource "azurerm_user_assigned_identity" "dev_vm"`,
		"the VM's identity must be user-assigned, so its lifetime and grants are independent of the VM")
}

// TestDefaultOutboundAccessIsExplicit -- Azure has retired implicit outbound
// access, so a subnet that does not state what it wants gets behaviour that
// depends on the provider's API version. The symptom is a VM where apt hangs.
func TestDefaultOutboundAccessIsExplicit(t *testing.T) {
	t.Parallel()

	config := code(readFile(t, networkModuleDir, "main.tf"))

	workloadSubnet := extractBlock(t, config, "azurerm_subnet", "workload")
	assertMatches(t, workloadSubnet, `default_outbound_access_enabled\s*=\s*false`,
		"the workload subnet must disable default outbound access explicitly")

	assert.Contains(t, config, `resource "azurerm_nat_gateway" "this"`,
		"with no default outbound access a NAT Gateway is mandatory, not optional")
	assert.Contains(t, config, `resource "azurerm_subnet_nat_gateway_association" "workload"`,
		"the NAT Gateway must actually be associated with the workload subnet")
}

// TestBastionSkuHandling -- the Developer SKU takes virtual_network_id and no
// ip_configuration; Basic and Standard are the opposite. Getting this wrong is an
// apply-time provider error, but the SKU-conditional wiring is easy to break
// silently while editing the block.
func TestBastionSkuHandling(t *testing.T) {
	t.Parallel()

	bastion := extractBlock(t, code(readFile(t, infrastructureDir, "main.tf")), "azurerm_bastion_host", "this")

	assertMatches(t, bastion, `virtual_network_id\s*=\s*var\.bastion_sku == "Developer" \?`,
		"virtual_network_id is only accepted for the Developer SKU")
	assertMatches(t, bastion, `tunneling_enabled\s*=\s*var\.bastion_sku == "Standard" \?`,
		"tunneling is only accepted for Standard and above")
	assert.Contains(t, bastion, `dynamic "ip_configuration"`,
		"ip_configuration must be conditional: Developer SKU must not have one")
}

// --- helpers ---------------------------------------------------------------

func readFile(t *testing.T, dir string, name string) string {
	t.Helper()

	content, err := os.ReadFile(filepath.Join(dir, name))
	require.NoError(t, err, "reading %s", filepath.Join(dir, name))

	return string(content)
}

// code strips whole-line comments so assertions read configuration rather than
// the prose that explains it.
func code(config string) string {
	lines := strings.Split(config, "\n")
	kept := make([]string, 0, len(lines))

	for _, line := range lines {
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		kept = append(kept, line)
	}

	return strings.Join(kept, "\n")
}

// extractBlock returns one resource block, from its opening line to the next line
// that closes a brace in column zero. Crude, and sufficient: the configuration is
// `terraform fmt` clean, so top-level blocks always close in column zero. Pass an
// empty name to take the first block of that type.
func extractBlock(t *testing.T, config string, resourceType string, name string) string {
	t.Helper()

	header := `resource "` + resourceType + `"`
	if name != "" {
		header = header + ` "` + name + `"`
	}

	start := strings.Index(config, header)
	require.NotEqual(t, -1, start, "no %s block found", header)

	end := strings.Index(config[start:], "\n}\n")
	require.NotEqual(t, -1, end, "unterminated %s block", header)

	return config[start : start+end]
}

func assertMatches(t *testing.T, content string, pattern string, message string) {
	t.Helper()

	assert.Regexp(t, regexp.MustCompile(pattern), content, message)
}

func assertDoesNotMatch(t *testing.T, content string, pattern string, message string) {
	t.Helper()

	assert.NotRegexp(t, regexp.MustCompile(pattern), content, message)
}
