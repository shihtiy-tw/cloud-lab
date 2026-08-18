variable "project_name" {
  description = "Project or application name; used to name and tag resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "test", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, test, prod."
  }
}

variable "location" {
  description = "Cloud location to deploy into."
  type        = string
  default     = "eastus"
}

variable "owner" {
  description = "Team or individual responsible for these resources."
  type        = string
  default     = ""
}

variable "cost_center" {
  description = "Cost allocation code."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags merged into the common tag set."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Azure resource group to deploy into."
  type        = string
}

variable "create_resource_group" {
  description = "Create the resource group rather than adopting an existing one. See the network module for why the default is false."
  type        = bool
  default     = false
}

variable "subscription_id" {
  description = <<-EOT
    Subscription to deploy into. Empty falls back to ARM_SUBSCRIPTION_ID (or the
    az CLI's current subscription), which is what CI and Terratest use.

    azurerm 4.x and later require this to be resolvable at plan time, but not at
    validate time -- which is why `terraform validate` still works with no
    credentials at all.
  EOT
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vnet_cidr" {
  description = "Address space for the VM's virtual network."
  type        = string
  default     = "10.30.0.0/16"
}

variable "subnet_cidr" {
  description = "Workload subnet prefix. Empty derives a /24 from vnet_cidr."
  type        = string
  default     = ""
}

variable "bastion_subnet_cidr" {
  description = "AzureBastionSubnet prefix, used only for the Basic/Standard SKUs. Empty derives a /26 from the top of vnet_cidr."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Image
# ---------------------------------------------------------------------------

variable "image_id" {
  description = <<-EOT
    Explicit image resource id to boot from, overriding the gallery lookup below.
    Set this to the id printed by `packer build` to guarantee the exact image
    version, or to a marketplace/managed image id to boot something else entirely.
  EOT
  type        = string
  default     = ""
}

variable "gallery_name" {
  description = "Compute Gallery holding the dev-vm image. Default matches shared/packer's azure_gallery_name."
  type        = string
  default     = "cloudlab"
}

variable "gallery_resource_group_name" {
  description = "Resource group holding the Compute Gallery. Default matches shared/packer's azure_gallery_resource_group."
  type        = string
  default     = "cloud-lab-images"
}

variable "gallery_image_name" {
  description = "Image definition inside the gallery. Default matches shared/packer's azure_gallery_image_name."
  type        = string
  default     = "dev-vm"
}

variable "image_version" {
  description = <<-EOT
    Gallery image version to boot, e.g. "0.1.0".

    Pinned on purpose. "latest" is a valid value for the data source, but
    source_image_id is a ForceNew attribute: the next `packer build` would publish
    a new version and the following `terraform apply` would silently destroy and
    recreate the VM. The home directory survives that (it lives on the persistent
    data disk) but anything on the OS disk does not. Bump this deliberately.
  EOT
  type        = string
  default     = "0.1.0"

  validation {
    condition     = var.image_version != "latest"
    error_message = "image_version must be an explicit version. \"latest\" makes every new gallery version force a VM replacement on the next apply."
  }
}

# ---------------------------------------------------------------------------
# VM
# ---------------------------------------------------------------------------

variable "vm_size" {
  description = <<-EOT
    VM size. Standard_D2s_v5 matches the size shared/packer builds on.

    Prefer a size with no local temporary disk (the Dsv5 family) over one that
    has one (Ddsv5, Dv3, ...). shared/bootstrap/seed-home.sh falls back to "the
    first blank disk" when it runs before cloud-init has written
    /etc/dev-vm/seed-home.env, and on a size with a temp disk that fallback can
    pick the temp disk -- whose contents vanish on deallocation. No temp disk, no
    ambiguity.
  EOT
  type        = string
  default     = "Standard_D2s_v5"
}

variable "availability_zone" {
  description = <<-EOT
    Availability zone ("1", "2", "3") for the VM and its home disk, or empty for
    a regional (non-zonal) deployment.

    Empty by default. A zonal VM pins the persistent home disk to the same zone
    forever -- the disk cannot be moved later without a snapshot-and-restore --
    and a single dev VM gains nothing from zone placement unless it has to sit
    next to zonal resources.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "1", "2", "3"], var.availability_zone)
    error_message = "availability_zone must be \"\", \"1\", \"2\", or \"3\"."
  }
}

variable "admin_username" {
  description = <<-EOT
    Local admin user Azure provisions on the VM.

    Must match the target_user the image was built with (default "ubuntu"): the
    baked home seed in /opt/dev-vm/home-seed belongs to that user, and this value
    is written straight into TARGET_USER in /etc/dev-vm/seed-home.env. A mismatch
    produces a VM whose dotfiles are installed for a user that no longer exists.
  EOT
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_keys" {
  description = <<-EOT
    SSH public keys for admin_username. At least one is required: password
    authentication is disabled, so this is the only credential on the box.

    These keys are still needed even though nothing listens on the internet --
    Bastion tunnels an SSH session to the VM's private address, and sshd on the
    other end still wants a key. The key never crosses the public internet.
  EOT
  type        = list(string)
  default     = []
}

variable "os_disk_size_gb" {
  description = "OS disk size. Empty (null) keeps the size baked into the image; it can only ever grow."
  type        = number
  default     = null
}

variable "os_disk_storage_account_type" {
  description = "OS disk type. Premium_LRS keeps shell and editor startup snappy; StandardSSD_LRS is cheaper."
  type        = string
  default     = "Premium_LRS"
}

variable "encryption_at_host_enabled" {
  description = <<-EOT
    Encrypt the VM's disk data, caches, and temp disk in the host rather than only
    at the storage service.

    True by default, but it requires the EncryptionAtHost feature to be registered
    on the subscription, which is a one-off and easy to hit on day one:

      az feature register --namespace Microsoft.Compute --name EncryptionAtHost
      az provider register --namespace Microsoft.Compute

    Without it the apply fails with a feature-not-enabled error. Set false to
    proceed with platform-managed encryption at rest only.
  EOT
  type        = bool
  default     = true
}

variable "secure_boot_enabled" {
  description = "Trusted launch secure boot. The Packer image is Gen2, so this is available; disable it if you boot an image that is not trusted-launch capable."
  type        = bool
  default     = true
}

variable "vtpm_enabled" {
  description = "Trusted launch vTPM. Same caveat as secure_boot_enabled."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Persistent home disk
# ---------------------------------------------------------------------------

variable "data_disk_size_gb" {
  description = "Size of the persistent home disk. This is the disk that survives `terraform destroy`."
  type        = number
  default     = 128
}

variable "data_disk_storage_account_type" {
  description = "Home disk type. Premium_LRS because this disk holds the working tree and every git operation touches it."
  type        = string
  default     = "Premium_LRS"
}

# ---------------------------------------------------------------------------
# Bastion
# ---------------------------------------------------------------------------

variable "create_bastion" {
  description = <<-EOT
    Create the Bastion host.

    False is a legitimate configuration when a Bastion already exists in the VNet
    (one Bastion serves every VM in it, and it is the expensive part), or when
    you intend to create it out of band with `az network bastion create`.
  EOT
  type        = bool
  default     = true
}

variable "bastion_sku" {
  description = <<-EOT
    Bastion SKU, which is the one real decision in this stack:

      Developer  Free, platform-hosted, no AzureBastionSubnet, no public IP of
                 ours. Region-limited, and it serves one VM connection at a time.
                 Browser/portal connections; the provider forbids
                 tunneling_enabled here, so no `az network bastion ssh`.
      Basic      Dedicated instances in AzureBastionSubnet, ~$140/month. The
                 provider also forbids tunneling_enabled on Basic, so this is
                 still portal-only -- Basic buys you dedicated capacity, not a
                 native client.
      Standard   Same again plus native-client tunneling, which is what makes
                 `az network bastion ssh`, scp, and VS Code Remote-SSH work.
                 Pick this if you want a real terminal instead of a browser tab.

    Those SKU/feature constraints are enforced by the azurerm provider itself
    (`tunneling_enabled is only supported when sku is Standard or Premium`), not
    just by documentation.
  EOT
  type        = string
  default     = "Developer"

  validation {
    condition     = contains(["Developer", "Basic", "Standard"], var.bastion_sku)
    error_message = "bastion_sku must be one of: Developer, Basic, Standard."
  }
}

variable "bastion_scale_units" {
  description = "Instance count for the Standard SKU. Ignored for Developer and Basic, where the provider rejects it (Basic is always 2)."
  type        = number
  default     = 2
}

variable "bastion_ssh_source_address_prefix" {
  description = "Source scope allowed inbound on 22. Passed through to the network module, which refuses internet-wide values."
  type        = string
  default     = "VirtualNetwork"
}

# ---------------------------------------------------------------------------
# Identity and access
# ---------------------------------------------------------------------------

variable "identity_role_assignments" {
  description = <<-EOT
    Role assignments granted to the VM's user-assigned managed identity, as
    [{ role_definition_name, scope }].

    Empty by default, and that is the point. This identity exists so the box can
    call Azure without a stored credential, not so it can administer the
    subscription. Grant it the narrowest role on the narrowest scope the work
    actually needs -- a specific Key Vault, a specific storage account -- and
    never Contributor or Owner at subscription scope. The human's own Entra
    identity is where admin rights belong; see developer_principal_ids.
  EOT
  type = list(object({
    role_definition_name = string
    scope                = string
  }))
  default = []

  validation {
    condition = alltrue([
      for assignment in var.identity_role_assignments :
      !contains(["Owner", "Contributor", "User Access Administrator"], assignment.role_definition_name)
    ])
    error_message = "The VM identity must not be Owner, Contributor, or User Access Administrator. Scope a narrower built-in role, or a custom one."
  }
}

variable "developer_principal_ids" {
  description = <<-EOT
    Entra object ids of the humans who may use this VM.

    These assignments are what actually grant access -- creating a Bastion does
    not. Each principal gets Reader on the VM, its NIC, and the Bastion host
    (Bastion's portal and CLI flows all read those three), plus a VM login role
    so Entra credentials work at the sshd prompt.
  EOT
  type        = list(string)
  default     = []
}

variable "developer_vm_login_role" {
  description = <<-EOT
    Login role granted to developer_principal_ids.

    "Virtual Machine Administrator Login" grants sudo, which is the right answer
    for a personal dev box that installs packages. Downgrade to "Virtual Machine
    User Login" for a shared or demo VM.
  EOT
  type        = string
  default     = "Virtual Machine Administrator Login"

  validation {
    condition     = contains(["Virtual Machine Administrator Login", "Virtual Machine User Login"], var.developer_vm_login_role)
    error_message = "developer_vm_login_role must be \"Virtual Machine Administrator Login\" or \"Virtual Machine User Login\"."
  }
}

variable "enable_aad_ssh_login" {
  description = <<-EOT
    Install the AADSSHLoginForLinux extension.

    Without it the VM login role assignments above are inert: nothing on the box
    knows how to check an Entra token, so only the SSH keys in ssh_public_keys
    work. With it, `az ssh vm` / `az network bastion ssh --auth-type AAD`
    authenticate against Entra and honour those role assignments -- which is how
    access is revoked by removing a role instead of by rotating a key.
  EOT
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Auto-stop: scheduled (Terraform) and idle-based (on-box)
# ---------------------------------------------------------------------------

variable "auto_stop_enabled" {
  description = "Enable the nightly scheduled shutdown. The schedule resource is created either way so it can be flipped without recreating it."
  type        = bool
  default     = true
}

variable "auto_stop_time" {
  description = "Daily shutdown time as HHmm in auto_stop_timezone, e.g. \"2000\" for 8pm."
  type        = string
  default     = "2000"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3])[0-5][0-9]$", var.auto_stop_time))
    error_message = "auto_stop_time must be a 24-hour HHmm string, e.g. \"2000\"."
  }
}

variable "auto_stop_timezone" {
  description = "Windows timezone name for the schedule (Azure uses Windows names, e.g. \"UTC\", \"Taipei Standard Time\", \"Pacific Standard Time\")."
  type        = string
  default     = "UTC"
}

variable "auto_stop_notification_enabled" {
  description = "Send a warning before the scheduled shutdown, so a long-running job can be rescued."
  type        = bool
  default     = false
}

variable "auto_stop_notification_email" {
  description = "Email for the shutdown warning. Required by Azure when notifications are enabled."
  type        = string
  default     = ""
}

variable "auto_stop_notification_minutes" {
  description = "How long before shutdown to warn. Azure's minimum is 15."
  type        = number
  default     = 30
}

variable "idle_shutdown_enabled" {
  description = "Enable the on-box idle shutdown timer baked into the image. The scheduled shutdown above is the backstop for when the box wedges."
  type        = bool
  default     = true
}

variable "idle_shutdown_minutes" {
  description = "Consecutive idle minutes before the on-box timer powers the VM off."
  type        = number
  default     = 30

  validation {
    condition     = var.idle_shutdown_minutes >= 5
    error_message = "idle_shutdown_minutes must be at least 5, the interval at which the on-box timer checks."
  }
}

variable "idle_shutdown_load_threshold" {
  description = "1-minute load average below which the box counts as idle. Raise it on a busy VM whose baseline load is above 0.5."
  type        = string
  default     = "0.5"
}

variable "idle_shutdown_ignore_containers" {
  description = "Treat running containers as idle. False keeps a kind cluster or a dev database from being shut out from under you."
  type        = bool
  default     = false
}
