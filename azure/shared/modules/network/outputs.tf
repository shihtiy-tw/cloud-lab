output "resource_group_name" {
  description = "Resource group the network lives in, whether created here or pre-existing."
  value       = local.resource_group_name
}

output "vnet_id" {
  description = "Virtual network id. Also what the Developer-SKU Bastion host attaches to."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Virtual network name."
  value       = azurerm_virtual_network.this.name
}

output "subnet_id" {
  description = "Workload subnet id. No default outbound access; egress is via the NAT Gateway."
  value       = azurerm_subnet.workload.id
}

output "subnet_name" {
  description = "Workload subnet name."
  value       = azurerm_subnet.workload.name
}

output "subnet_cidr" {
  description = "Workload subnet address prefix."
  value       = local.subnet_cidr
}

output "nat_gateway_id" {
  description = "NAT Gateway id. The subnet's only path to the internet, and outbound only."
  value       = azurerm_nat_gateway.this.id
}

output "nat_public_ip_address" {
  description = "Outbound source address of the subnet. Useful for allow-listing this VM at the far end; it grants no inbound reachability."
  value       = azurerm_public_ip.nat.ip_address
}

output "network_security_group_id" {
  description = "NSG attached to the workload subnet."
  value       = azurerm_network_security_group.workload.id
}

output "network_security_group_name" {
  description = "NSG name, so callers can add scoped rules without importing the group."
  value       = azurerm_network_security_group.workload.name
}

output "bastion_subnet_id" {
  description = "AzureBastionSubnet id, or null when create_bastion_subnet is false (Developer SKU needs no subnet)."
  value       = var.create_bastion_subnet ? azurerm_subnet.bastion[0].id : null
}

output "inbound_security_rules" {
  description = <<-EOT
    Every inbound rule this module creates, as {name, access, source}. Exists so a
    test or a reviewer can assert the security property directly instead of
    reading the plan: no entry here may have an internet-wide source.
  EOT
  value = [
    {
      name   = azurerm_network_security_rule.allow_bastion_ssh_inbound.name
      access = azurerm_network_security_rule.allow_bastion_ssh_inbound.access
      source = azurerm_network_security_rule.allow_bastion_ssh_inbound.source_address_prefix
    },
    {
      name   = azurerm_network_security_rule.deny_all_inbound.name
      access = azurerm_network_security_rule.deny_all_inbound.access
      source = azurerm_network_security_rule.deny_all_inbound.source_address_prefix
    },
  ]
}
