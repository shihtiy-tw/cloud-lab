# azure compute - dev-vm
#
# A personal Ubuntu development VM built from the Compute Gallery image that
# shared/packer produces, reachable only through Azure Bastion.
#
# The requirement this stack exists to satisfy: "Do not use ssh to open to public
# network, use cloud-native secure way for connection." On Azure that is Bastion,
# and it holds because of four properties that are worth checking on every review:
#
#   1. The NIC has no public IP. Nothing on this VM has an internet-routable
#      address; the only public IP in the design belongs to the NAT Gateway,
#      which is outbound-only.
#   2. The NSG allows nothing inbound from the internet. Bastion is out-of-band:
#      it terminates the session on its own instances and reaches the VM as
#      ordinary VNet traffic, so the only inbound allowance is VNet-scoped 22.
#   3. Password authentication is off and no password exists.
#   4. Access is granted by Entra role assignments, not by network position.
#
# Layout of what follows: identity, network (module), image, disks, NIC, VM,
# Bastion, auto-stop, RBAC.

locals {
  name = "${var.project_name}-dev-vm-${var.environment}"

  # Required tags per docs/standards/TAGGING_STANDARDS.md
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Component   = "compute"
      Owner       = var.owner
      CostCenter  = var.cost_center
    },
    var.tags
  )

  # Developer-SKU Bastion is a platform-hosted service that attaches to the VNet
  # itself: no AzureBastionSubnet, no public IP of ours. Basic and Standard need
  # both. Deriving it once here keeps the module call and the Bastion resource
  # from disagreeing.
  bastion_needs_subnet = var.create_bastion && var.bastion_sku != "Developer"

  # The device path shared/bootstrap/seed-home.sh will look for. lunN in the path
  # is the `lun` on the data disk attachment below; see data_disk_lun.
  data_disk_lun    = 0
  data_disk_device = "/dev/disk/azure/scsi1/lun${local.data_disk_lun}"

  source_image_id = var.image_id != "" ? var.image_id : data.azurerm_shared_image_version.dev_vm[0].id

  # A zonal VM needs its data disk in the same zone, so both read this.
  zone = var.availability_zone != "" ? var.availability_zone : null

  custom_data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    # TARGET_USER must be the user Azure provisions, or the seeded home belongs to
    # nobody. Same variable feeds both, so they cannot drift.
    target_user      = var.admin_username
    home_seed_dir    = "/opt/dev-vm/home-seed"
    fs_label         = "devhome"
    data_disk_device = local.data_disk_device

    idle_enabled      = var.idle_shutdown_enabled ? "true" : "false"
    idle_minutes      = var.idle_shutdown_minutes
    load_threshold    = var.idle_shutdown_load_threshold
    ignore_containers = var.idle_shutdown_ignore_containers ? "true" : "false"
    # Fixed at 5 to match OnUnitActiveSec in dev-vm-idle-shutdown.timer, which
    # lives on the image. The script accumulates idle time in units of this
    # interval, so a value that disagrees with the timer makes IDLE_MINUTES mean
    # something other than minutes.
    check_interval_minutes = 5
  })
}

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

# A user-assigned identity, created empty. The VM gets an Azure credential
# without one being stored on disk, and its permissions are whatever
# var.identity_role_assignments grants -- by default, nothing.
#
# This is deliberately not an admin identity. Anyone who can run code on the VM
# can mint tokens for it from IMDS, so Contributor here would mean "shell on the
# dev box implies subscription takeover". Administrative rights belong to the
# human's own Entra identity, which is what var.developer_principal_ids wires up,
# and which is auditable and revocable per person.
resource "azurerm_user_assigned_identity" "dev_vm" {
  name                = "${local.name}-id"
  location            = var.location
  resource_group_name = module.network.resource_group_name

  tags = local.common_tags
}

resource "azurerm_role_assignment" "identity" {
  for_each = {
    for index, assignment in var.identity_role_assignments :
    "${index}-${assignment.role_definition_name}" => assignment
  }

  principal_id         = azurerm_user_assigned_identity.dev_vm.principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = each.value.role_definition_name
  scope                = each.value.scope
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

module "network" {
  source = "../../../shared/modules/network"

  project_name        = var.project_name
  environment         = var.environment
  location            = var.location
  resource_group_name = var.resource_group_name

  create_resource_group             = var.create_resource_group
  vnet_cidr                         = var.vnet_cidr
  subnet_cidr                       = var.subnet_cidr
  create_bastion_subnet             = local.bastion_needs_subnet
  bastion_subnet_cidr               = var.bastion_subnet_cidr
  bastion_ssh_source_address_prefix = var.bastion_ssh_source_address_prefix

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Image
# ---------------------------------------------------------------------------

# The gallery image version built by shared/packer. Looked up by exact version
# rather than "latest" on purpose: source_image_id forces replacement, so a
# `latest` lookup turns every new Packer build into a VM rebuild on the next
# apply, at whatever moment someone happens to run one.
data "azurerm_shared_image_version" "dev_vm" {
  count = var.image_id == "" ? 1 : 0

  name                = var.image_version
  image_name          = var.gallery_image_name
  gallery_name        = var.gallery_name
  resource_group_name = var.gallery_resource_group_name
}

# ---------------------------------------------------------------------------
# Persistent home disk
# ---------------------------------------------------------------------------

# /home/<user> lives here, not on the OS disk. That is the whole lifecycle
# design: destroy the VM nightly or weekly and keep the working trees, shell
# history, and credentials.
resource "azurerm_managed_disk" "home" {
  name                = "${local.name}-home"
  location            = var.location
  resource_group_name = module.network.resource_group_name
  zone                = local.zone

  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
  storage_account_type = var.data_disk_storage_account_type

  # Encrypted at rest with platform-managed keys by default -- there is no way to
  # create an unencrypted managed disk. Set disk_encryption_set_id if the
  # requirement is customer-managed keys; that needs a Key Vault and a disk
  # encryption set, which is out of scope for a personal dev box.

  # Keep this disk out of the blast radius of a stray destroy. Terraform will
  # refuse to plan a destroy that includes it -- which means `make destroy`
  # cannot silently delete a home directory. Detaching it (removing the VM) is
  # allowed and is the intended cost-saving path.
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name}-home"
    Purpose = "persistent-home"
  })
}

resource "azurerm_virtual_machine_data_disk_attachment" "home" {
  managed_disk_id    = azurerm_managed_disk.home.id
  virtual_machine_id = azurerm_linux_virtual_machine.dev_vm.id
  caching            = "ReadWrite"

  # lun 0 is load-bearing. Azure exposes data disks at
  # /dev/disk/azure/scsi1/lunN, and DATA_DISK_DEVICE in the cloud-init above is
  # /dev/disk/azure/scsi1/lun0. Change this number and seed-home.sh looks for a
  # device that does not exist, then either fails the unit or silently falls
  # through to the OS disk's copy of the home directory.
  lun = local.data_disk_lun
}

# ---------------------------------------------------------------------------
# NIC and VM
# ---------------------------------------------------------------------------

resource "azurerm_network_interface" "dev_vm" {
  name                = "${local.name}-nic"
  location            = var.location
  resource_group_name = module.network.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.network.subnet_id
    private_ip_address_allocation = "Dynamic"

    # There is deliberately no public_ip_address_id here, and this is the single
    # most important line of the stack -- by being absent.
    #
    # The design does contain a public IP, on the NAT Gateway in the network
    # module. That one is necessary: it is the subnet's outbound source address
    # and accepts nothing inbound. This one would be the opposite: an
    # internet-routable address on the VM itself. If a "the VM has no public IP,
    # is that a mistake?" review question arrives, the answer is that the NAT
    # Gateway already provides egress and Bastion already provides ingress, so a
    # public IP here would add nothing except an attack surface.
  }

  tags = local.common_tags
}

resource "azurerm_linux_virtual_machine" "dev_vm" {
  name                = local.name
  location            = var.location
  resource_group_name = module.network.resource_group_name
  size                = var.vm_size
  zone                = local.zone

  network_interface_ids = [azurerm_network_interface.dev_vm.id]
  source_image_id       = local.source_image_id

  admin_username = var.admin_username

  # No admin_password anywhere in this file, and password auth off in sshd. A
  # password would be the one credential that a brute-forceable path could ever
  # use, and it is also the credential most likely to end up in a tfvars file.
  disable_password_authentication = true

  dynamic "admin_ssh_key" {
    for_each = toset(var.ssh_public_keys)

    content {
      username   = var.admin_username
      public_key = admin_ssh_key.value
    }
  }

  # Encrypt disk data, caches, and any temp disk in the host, not just at the
  # storage service. Requires the EncryptionAtHost feature registered on the
  # subscription -- see the variable's description for the two az commands. This
  # is the most common day-one apply failure in this stack.
  encryption_at_host_enabled = var.encryption_at_host_enabled

  # Trusted launch. The Packer image is Gen2, so these are available; they are
  # free and they make firmware-level tampering detectable.
  secure_boot_enabled = var.secure_boot_enabled
  vtpm_enabled        = var.vtpm_enabled

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_account_type
    disk_size_gb         = var.os_disk_size_gb
    # Platform-managed encryption at rest applies to every managed disk and
    # cannot be turned off; encryption_at_host_enabled above extends it to the
    # data in flight between the host and storage.
  }

  identity {
    # SystemAssigned is here only because the AADSSHLoginForLinux extension
    # requires it -- Entra login is implemented as the VM authenticating itself
    # to Entra, which it cannot do with a user-assigned identity alone. The
    # user-assigned identity is the one that carries any workload permissions.
    type         = var.enable_aad_ssh_login ? "SystemAssigned, UserAssigned" : "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.dev_vm.id]
  }

  # Break-glass. With no SSH from the internet, a broken Bastion is a lockout, so
  # the serial console has to work before it is needed. An empty block uses the
  # platform-managed storage account, which means there is no storage account of
  # ours to forget to create, and no key to manage. See the README's recovery
  # section for the path from here to a root prompt.
  boot_diagnostics {}

  custom_data = base64encode(local.custom_data)

  tags = merge(local.common_tags, {
    Name = local.name
  })

  lifecycle {
    # Fail at plan time with a sentence instead of at apply time with an Azure
    # API error. Password auth is disabled, so a VM with no key is a VM nobody
    # can log into -- including through Bastion.
    precondition {
      condition     = length(var.ssh_public_keys) > 0
      error_message = "ssh_public_keys must contain at least one key. Password authentication is disabled, so it is the only credential on the VM; Bastion tunnels SSH to it over the VNet."
    }
  }
}

# Entra login. Without this extension the "Virtual Machine Administrator Login"
# role assignments below grant nothing: the box has no way to validate an Entra
# token, and only the keys in ssh_public_keys work. With it, access is granted and
# revoked by role assignment rather than by key distribution.
resource "azurerm_virtual_machine_extension" "aad_ssh_login" {
  count = var.enable_aad_ssh_login ? 1 : 0

  name                       = "AADSSHLoginForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.dev_vm.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true

  # The extension installs from the internet, so it depends on egress existing.
  # On a subnet with default outbound access disabled and no NAT Gateway this
  # times out after ~20 minutes with a provisioning error that says nothing about
  # networking.
  depends_on = [module.network]

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Bastion
# ---------------------------------------------------------------------------

# Only for Basic and Standard: the provider's own validation is "`ip_configuration`
# with `public_ip_address_id` is required when `sku` is `Basic` or `Standard`",
# and correspondingly "`virtual_network_id` is only supported when `sku` is
# `Developer`". This public IP belongs to Bastion, which is a managed service
# fronting an authenticated, RBAC-gated session broker -- it is not an SSH port.
resource "azurerm_public_ip" "bastion" {
  count = local.bastion_needs_subnet ? 1 : 0

  name                = "${local.name}-bastion-pip"
  location            = var.location
  resource_group_name = module.network.resource_group_name

  # Bastion requires Standard SKU, static allocation. Basic is rejected.
  allocation_method = "Static"
  sku               = "Standard"

  tags = local.common_tags
}

resource "azurerm_bastion_host" "this" {
  count = var.create_bastion ? 1 : 0

  name                = "${local.name}-bastion"
  location            = var.location
  resource_group_name = module.network.resource_group_name
  sku                 = var.bastion_sku

  # Developer SKU: the host attaches to the VNet directly and Azure supplies the
  # capacity. azurerm 5.1 expresses this natively, so no `az network bastion
  # create --sku Developer` shim is needed -- see the README if you are pinned to
  # an older provider that cannot omit ip_configuration.
  virtual_network_id = var.bastion_sku == "Developer" ? module.network.vnet_id : null

  # Native-client tunneling -- `az network bastion ssh`, scp, VS Code Remote-SSH
  # -- is Standard and above. The provider rejects it on Developer and Basic, so
  # those two SKUs mean browser-based sessions only. This is the practical reason
  # to pay for Standard.
  tunneling_enabled  = var.bastion_sku == "Standard" ? true : null
  file_copy_enabled  = var.bastion_sku == "Standard" ? true : null
  ip_connect_enabled = var.bastion_sku == "Standard" ? false : null
  scale_units        = var.bastion_sku == "Standard" ? var.bastion_scale_units : null

  dynamic "ip_configuration" {
    for_each = local.bastion_needs_subnet ? [1] : []

    content {
      name                 = "configuration"
      subnet_id            = module.network.bastion_subnet_id
      public_ip_address_id = azurerm_public_ip.bastion[0].id
    }
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# How to connect, assembled once and emitted as an output
# ---------------------------------------------------------------------------

# Built here rather than in outputs.tf because the SKU decision changes the
# instructions completely, and a wrong instruction on a box with no SSH fallback
# costs an afternoon.
locals {
  # one() is null-safe for count = 0, unlike [0]; try() then keeps a null from
  # propagating into string interpolation, which is a hard error.
  bastion_host      = one(azurerm_bastion_host.this)
  bastion_host_id   = try(local.bastion_host.id, null)
  bastion_host_name = try(local.bastion_host.name, null)

  bastion_native_client_supported = var.create_bastion && var.bastion_sku == "Standard"

  # Joined rather than written as a heredoc: a heredoc's indentation is stripped
  # relative to its own body, so interpolating one inside another loses the
  # continuation indent and the result no longer copy-pastes.
  connect_command_arguments = join(" \\\n", [
    "--name ${coalesce(local.bastion_host_name, "<bastion-name>")}",
    "--resource-group ${module.network.resource_group_name}",
    "--target-resource-id ${azurerm_linux_virtual_machine.dev_vm.id}",
  ])

  connect_auth_arguments = var.enable_aad_ssh_login ? "--auth-type AAD" : "--auth-type ssh-key --username ${var.admin_username} --ssh-key ~/.ssh/id_ed25519"

  connect_native_client = <<-EOT
    Native client, because this Bastion is Standard SKU with tunneling enabled:

    az network bastion ssh \
    ${local.connect_command_arguments} \
    ${local.connect_auth_arguments}

    For scp, VS Code Remote-SSH, or forwarding a dev server, open a tunnel and
    treat it as a local port:

    az network bastion tunnel \
    ${local.connect_command_arguments} \
    --resource-port 22 --port 2222

    ssh ${var.admin_username}@127.0.0.1 -p 2222
  EOT

  connect_browser_only = <<-EOT
    Browser only. The ${var.bastion_sku} SKU does not support native-client
    tunneling -- the azurerm provider rejects tunneling_enabled on anything below
    Standard -- so `az network bastion ssh` cannot reach this VM. Use the portal
    path below, or set bastion_sku = "Standard" if you need a local terminal,
    scp, or VS Code Remote-SSH.
  EOT

  connection_instructions = <<-EOT
    VM:             ${azurerm_linux_virtual_machine.dev_vm.name}
    Resource group: ${module.network.resource_group_name}
    Private IP:     ${azurerm_linux_virtual_machine.dev_vm.private_ip_address}
    Public IP:      none, by design -- Bastion is the only way in
    Bastion:        ${coalesce(local.bastion_host_name, "not created by this stack")}${var.create_bastion ? " (${var.bastion_sku} SKU)" : ""}

    The auto-stop will have stopped it; start it first:

      az vm start --name ${azurerm_linux_virtual_machine.dev_vm.name} --resource-group ${module.network.resource_group_name}

    ${local.bastion_native_client_supported ? local.connect_native_client : local.connect_browser_only}
    Portal: Virtual machines -> ${azurerm_linux_virtual_machine.dev_vm.name} -> Connect -> Bastion

    Break-glass, if Bastion itself is broken:

      az vm boot-diagnostics get-boot-log --name ${azurerm_linux_virtual_machine.dev_vm.name} --resource-group ${module.network.resource_group_name}

    then Portal -> the VM -> Help -> Serial console for a root prompt that does
    not depend on the network stack at all.
  EOT
}

# ---------------------------------------------------------------------------
# Auto-stop
# ---------------------------------------------------------------------------

# The cheap trick in this stack: azurerm_dev_test_global_vm_shutdown_schedule
# works on any ordinary VM, not only on DevTest Labs VMs. It is a free
# Microsoft.DevTestLab schedule resource attached to the VM, so a nightly stop
# costs nothing and needs no Automation account, Logic App, or Function.
#
# Two layers on purpose: this one is the clock-based backstop for a wedged box,
# and the on-box idle timer (configured through cloud-init) is what reacts to
# actual idleness. Either alone leaves a gap -- the timer cannot save a hung VM,
# and the schedule cannot stop a box that has been idle since 9am.
resource "azurerm_dev_test_global_vm_shutdown_schedule" "dev_vm" {
  virtual_machine_id = azurerm_linux_virtual_machine.dev_vm.id
  location           = var.location
  enabled            = var.auto_stop_enabled

  daily_recurrence_time = var.auto_stop_time
  # Azure wants Windows timezone names here ("Taipei Standard Time"), not IANA
  # ones ("Asia/Taipei"). An IANA name is accepted by Terraform and rejected by
  # the API.
  timezone = var.auto_stop_timezone

  notification_settings {
    enabled         = var.auto_stop_notification_enabled
    email           = var.auto_stop_notification_email != "" ? var.auto_stop_notification_email : null
    time_in_minutes = var.auto_stop_notification_enabled ? var.auto_stop_notification_minutes : null
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# RBAC for the humans
# ---------------------------------------------------------------------------

# These assignments are what actually grant access to this VM. Creating a Bastion
# host grants nobody anything: a principal with no roles sees no VM to connect to
# and gets an authorization error from the session broker.
#
# Bastion's portal and CLI flows read the VM, the NIC that holds its private
# address, and the Bastion resource itself, so Reader is needed on all three --
# Reader on the VM alone produces a "connect" button that fails.

resource "azurerm_role_assignment" "developer_vm_login" {
  for_each = toset(var.developer_principal_ids)

  principal_id         = each.value
  role_definition_name = var.developer_vm_login_role
  scope                = azurerm_linux_virtual_machine.dev_vm.id
  description          = "Entra-authenticated login to the dev VM. Inert without the AADSSHLoginForLinux extension."
}

resource "azurerm_role_assignment" "developer_vm_reader" {
  for_each = toset(var.developer_principal_ids)

  principal_id         = each.value
  role_definition_name = "Reader"
  scope                = azurerm_linux_virtual_machine.dev_vm.id
  description          = "Required for Bastion to broker a session to this VM."
}

resource "azurerm_role_assignment" "developer_nic_reader" {
  for_each = toset(var.developer_principal_ids)

  principal_id         = each.value
  role_definition_name = "Reader"
  scope                = azurerm_network_interface.dev_vm.id
  description          = "Bastion resolves the VM's private address through the NIC."
}

resource "azurerm_role_assignment" "developer_bastion_reader" {
  for_each = var.create_bastion ? toset(var.developer_principal_ids) : toset([])

  principal_id         = each.value
  role_definition_name = "Reader"
  scope                = azurerm_bastion_host.this[0].id
  description          = "Required to open a session through this Bastion host."
}
