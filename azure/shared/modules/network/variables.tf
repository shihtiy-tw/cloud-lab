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
  description = "Azure region to deploy into. Named `location`, not `region`, to match the rest of the Azure tree and the azurerm provider."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = <<-EOT
    Resource group for the network. Used as-is when create_resource_group is
    false, so an existing group can own these resources; used as the name of the
    group this module creates when it is true.
  EOT
  type        = string
}

variable "create_resource_group" {
  description = <<-EOT
    Create the resource group instead of reusing an existing one.

    False by default: in a shared subscription the group usually exists already
    and is governed by policy, and adopting it into this state would let a
    `terraform destroy` here take unrelated resources with it.
  EOT
  type        = bool
  default     = false
}

variable "vnet_cidr" {
  description = "Address space for the virtual network."
  type        = string
  default     = "10.30.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0))
    error_message = "vnet_cidr must be a valid CIDR block."
  }
}

variable "subnet_cidr" {
  description = <<-EOT
    Address prefix for the workload subnet. Empty derives a /24 from the first
    block of vnet_cidr, which assumes vnet_cidr is /16 or larger -- pass this
    explicitly for anything smaller.
  EOT
  type        = string
  default     = ""
}

variable "create_bastion_subnet" {
  description = <<-EOT
    Create the AzureBastionSubnet. Required for the Basic and Standard Bastion
    SKUs and forbidden for Developer, which is a platform-hosted service that
    attaches to the VNet itself and needs no subnet of ours.
  EOT
  type        = bool
  default     = false
}

variable "bastion_subnet_cidr" {
  description = <<-EOT
    Address prefix for AzureBastionSubnet. Azure rejects anything smaller than a
    /26. Empty derives a /26 from the far end of vnet_cidr so it never collides
    with workload subnets numbered from the front.
  EOT
  type        = string
  default     = ""
}

variable "bastion_ssh_source_address_prefix" {
  description = <<-EOT
    Source scope allowed inbound on port 22 to the workload subnet.

    "VirtualNetwork" is correct for every Bastion SKU: Bastion is out-of-band, it
    terminates the browser/CLI session on its own instances and then reaches the
    VM as ordinary VNet traffic. Nothing on the internet ever needs to be allowed
    in, which the validation below enforces rather than trusts.
  EOT
  type        = string
  default     = "VirtualNetwork"

  validation {
    condition = !contains(
      ["Internet", "internet", "*", "any", "Any", "0.0.0.0/0", "::/0", "AzureCloud"],
      var.bastion_ssh_source_address_prefix
    )
    error_message = "bastion_ssh_source_address_prefix must not be an internet-wide scope. The dev VM is reachable only through Bastion over the VNet; opening 22 to the internet is the exact thing this module exists to prevent."
  }
}

variable "nat_gateway_idle_timeout_in_minutes" {
  description = "Idle timeout for NAT Gateway flows. Four minutes is the Azure default; raising it holds SNAT ports longer."
  type        = number
  default     = 4
}

variable "tags" {
  description = "Additional tags merged into the common tag set. Applied last, so a caller can override any computed tag."
  type        = map(string)
  default     = {}
}
