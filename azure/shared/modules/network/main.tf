# Network for a private, brokered-access workload: one VNet, one workload subnet
# with no route to the internet of its own, a NAT Gateway for outbound only, and
# an NSG that allows nothing in from the internet.
#
# azure/compute/dev-vm is the reason this module exists. That VM has no public IP
# and is reached only through Azure Bastion, so the whole network contract is
# "egress yes, ingress no, and the only inbound allowance is VNet-scoped SSH so
# Bastion can land a session".

locals {
  name = "${var.project_name}-${var.environment}"

  # Required tags per aws/docs/standards/TAGGING_STANDARDS.md -- the same keys
  # are used across clouds so cost reports line up. var.tags comes last so a
  # caller (or a test) can override any of them.
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Component   = "networking"
    },
    var.tags
  )

  # Referencing the created group through the resource (rather than var directly)
  # keeps the implicit dependency, so nothing races the group into existence.
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  subnet_cidr = var.subnet_cidr != "" ? var.subnet_cidr : cidrsubnet(var.vnet_cidr, 8, 0)

  # Bastion's subnet is numbered from the top of the space so growing the
  # workload subnets from the bottom never has to renumber it. Renumbering a
  # subnet replaces it, and replacing AzureBastionSubnet means recreating the
  # Bastion host and its public IP.
  bastion_subnet_cidr = var.bastion_subnet_cidr != "" ? var.bastion_subnet_cidr : cidrsubnet(var.vnet_cidr, 10, 1023)
}

resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${local.name}-vnet"
  location            = var.location
  resource_group_name = local.resource_group_name
  address_space       = [var.vnet_cidr]

  tags = local.common_tags
}

# The workload subnet. Everything interesting about it is the one attribute
# below.
resource "azurerm_subnet" "workload" {
  name                 = "${local.name}-workload"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnet_cidr]

  # Azure's implicit "default outbound access" -- the platform SNAT that let any
  # VM reach the internet with no configuration -- is retired. Subnets created
  # through newer API versions get no implicit egress at all, so the difference
  # between "apt works" and "apt hangs" would otherwise depend on which azurerm
  # release happened to be installed. Set it false explicitly and provide egress
  # deliberately through the NAT Gateway below.
  default_outbound_access_enabled = false
}

# ---------------------------------------------------------------------------
# Egress: NAT Gateway
# ---------------------------------------------------------------------------

# This public IP is the NAT Gateway's, not a VM's. It gives the subnet a stable
# outbound source address and grants no inbound reachability whatsoever --
# unsolicited inbound traffic to a NAT Gateway is dropped. Do not "fix" the
# absence of a public IP on the VM's NIC by copying this; see the comment on the
# network interface in azure/compute/dev-vm.
resource "azurerm_public_ip" "nat" {
  name                = "${local.name}-nat-pip"
  location            = var.location
  resource_group_name = local.resource_group_name

  # NAT Gateway requires Standard SKU with a static allocation; Basic is not
  # accepted and is on its way out of the platform anyway.
  allocation_method = "Static"
  sku               = "Standard"

  tags = local.common_tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "${local.name}-nat"
  location                = var.location
  resource_group_name     = local.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.nat_gateway_idle_timeout_in_minutes

  tags = local.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "workload" {
  subnet_id      = azurerm_subnet.workload.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

# ---------------------------------------------------------------------------
# Ingress: none
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "workload" {
  name                = "${local.name}-workload-nsg"
  location            = var.location
  resource_group_name = local.resource_group_name

  # Rules are separate azurerm_network_security_rule resources rather than
  # inline security_rule blocks: the inline attribute is computed, so anything
  # that touches the NSG out-of-band (Azure Policy, a Bastion deployment) shows
  # up as drift on the whole group instead of on one rule.

  tags = local.common_tags
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

# The only inbound allowance in the whole module. Bastion instances live in the
# VNet (Basic/Standard) or attach to it as a platform service (Developer), and in
# both cases their traffic to the VM arrives as VNet-scoped traffic on 22. The
# variable's validation refuses any internet-wide source, so this rule cannot be
# widened by a tfvars edit alone.
resource "azurerm_network_security_rule" "allow_bastion_ssh_inbound" {
  name                        = "AllowBastionSshInbound"
  resource_group_name         = local.resource_group_name
  network_security_group_name = azurerm_network_security_group.workload.name

  priority                   = 300
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "22"
  source_address_prefix      = var.bastion_ssh_source_address_prefix
  destination_address_prefix = local.subnet_cidr
  description                = "SSH from Azure Bastion over the VNet. Never from the internet."
}

# Azure already ends every NSG with an implicit DenyAllInBound at priority 65500.
# Stating it at 4096 is defence in depth: it makes the intent auditable, it means
# a new Allow rule has to be given a priority that visibly precedes a deny rather
# than merely landing before an invisible default, and it survives someone
# deleting the rule above.
resource "azurerm_network_security_rule" "deny_all_inbound" {
  name                        = "DenyAllInbound"
  resource_group_name         = local.resource_group_name
  network_security_group_name = azurerm_network_security_group.workload.name

  priority                   = 4096
  direction                  = "Inbound"
  access                     = "Deny"
  protocol                   = "*"
  source_port_range          = "*"
  destination_port_range     = "*"
  source_address_prefix      = "*"
  destination_address_prefix = "*"
  description                = "Explicit deny-all inbound. Nothing from the internet reaches this subnet."
}

# ---------------------------------------------------------------------------
# AzureBastionSubnet (Basic and Standard SKUs only)
# ---------------------------------------------------------------------------

# The name is not a convention: Azure refuses to attach a Bastion host to any
# subnet not named exactly "AzureBastionSubnet".
resource "azurerm_subnet" "bastion" {
  count = var.create_bastion_subnet ? 1 : 0

  name                 = "AzureBastionSubnet"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.bastion_subnet_cidr]

  # Deliberately true here, unlike the workload subnet. Bastion's own control
  # traffic egresses through the public IP attached to the Bastion host, but
  # deployments into subnets with default outbound access disabled have a history
  # of failing to provision, and a Bastion that will not provision is a lockout.
  # The subnet that matters for the security property is the workload one.
  default_outbound_access_enabled = true
}

# No NSG is attached to AzureBastionSubnet on purpose. Azure requires a very
# specific rule set there (GatewayManager and AzureLoadBalancer inbound,
# AzureCloud and VirtualNetwork outbound, plus 8080/5701 between instances), and
# an incomplete one breaks Bastion in ways that look like a network fault. If a
# policy in your subscription mandates an NSG on every subnet, take the rule set
# from Microsoft's Bastion NSG documentation rather than improvising it.
