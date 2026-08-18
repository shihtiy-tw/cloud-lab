output "name" {
  description = "Generated base name for resources in this stack."
  value       = local.name
}

output "common_tags" {
  description = "Tag set applied to resources in this stack."
  value       = local.common_tags
}

output "vm_id" {
  description = "Resource id of the dev VM. Also the RBAC scope the login roles are granted on."
  value       = azurerm_linux_virtual_machine.dev_vm.id
}

output "vm_name" {
  description = "Name of the dev VM, as `az vm` and `az network bastion` want it."
  value       = azurerm_linux_virtual_machine.dev_vm.name
}

output "resource_group_name" {
  description = "Resource group holding the VM, disk, NIC, and Bastion."
  value       = module.network.resource_group_name
}

output "private_ip_address" {
  description = "The VM's only address. Routable inside the VNet and nowhere else."
  value       = azurerm_linux_virtual_machine.dev_vm.private_ip_address
}

output "admin_username" {
  description = "Local admin user, and the TARGET_USER written into /etc/dev-vm/seed-home.env."
  value       = var.admin_username
}

output "data_disk_id" {
  description = "Persistent home disk. Carries prevent_destroy, so it survives `make destroy` and is re-attached by the next apply."
  value       = azurerm_managed_disk.home.id
}

output "data_disk_device" {
  description = "Device path the VM's boot scripts mount as the home directory. Derived from the attachment's lun."
  value       = local.data_disk_device
}

output "identity_id" {
  description = "User-assigned managed identity resource id."
  value       = azurerm_user_assigned_identity.dev_vm.id
}

output "identity_principal_id" {
  description = "Principal id of the user-assigned identity, for granting it scoped roles elsewhere."
  value       = azurerm_user_assigned_identity.dev_vm.principal_id
}

output "identity_client_id" {
  description = "Client id of the user-assigned identity, for IMDS token requests from the box."
  value       = azurerm_user_assigned_identity.dev_vm.client_id
}

output "image_id" {
  description = "Exact image the VM booted from. Pinned; a change here replaces the VM."
  value       = local.source_image_id
}

output "network" {
  description = "Ids from the network module: vnet, workload subnet, NAT gateway, NSG."
  value = {
    vnet_id                   = module.network.vnet_id
    subnet_id                 = module.network.subnet_id
    subnet_cidr               = module.network.subnet_cidr
    nat_gateway_id            = module.network.nat_gateway_id
    network_security_group_id = module.network.network_security_group_id
    bastion_subnet_id         = module.network.bastion_subnet_id
  }
}

output "nat_public_ip_address" {
  description = <<-EOT
    The subnet's outbound source address, on the NAT Gateway. This is the design's
    only public IP, and it accepts nothing inbound -- do not confuse it with a
    public IP on the VM, which is what nic_has_public_ip proves does not exist.
  EOT
  value       = module.network.nat_public_ip_address
}

# ---------------------------------------------------------------------------
# The security properties, as outputs
# ---------------------------------------------------------------------------

# Exists so "does the VM have a public IP?" is answerable by `terraform output`
# and by a test, rather than by reading a plan or clicking through the portal.
output "nic_public_ip_ids" {
  description = "Public IPs attached to the VM's NIC. Must be empty; anything here is a security regression."
  value = [
    for configuration in azurerm_network_interface.dev_vm.ip_configuration :
    configuration.public_ip_address_id
    if configuration.public_ip_address_id != null && configuration.public_ip_address_id != ""
  ]
}

output "nic_has_public_ip" {
  description = "False is the requirement. The VM is reachable only through Bastion."
  value = length([
    for configuration in azurerm_network_interface.dev_vm.ip_configuration :
    configuration.public_ip_address_id
    if configuration.public_ip_address_id != null && configuration.public_ip_address_id != ""
  ]) > 0
}

output "inbound_security_rules" {
  description = "Every inbound NSG rule, as {name, access, source}. No entry may have an internet-wide source."
  value       = module.network.inbound_security_rules
}

output "password_authentication_disabled" {
  description = "True is the requirement. There is no admin_password anywhere in this stack."
  value       = azurerm_linux_virtual_machine.dev_vm.disable_password_authentication
}

# ---------------------------------------------------------------------------
# Connecting
# ---------------------------------------------------------------------------

output "bastion_host_id" {
  description = "Bastion host resource id, or null when create_bastion is false."
  value       = local.bastion_host_id
}

output "bastion_host_name" {
  description = "Bastion host name, or null when create_bastion is false."
  value       = local.bastion_host_name
}

output "bastion_sku" {
  description = "Bastion SKU in effect. Only Standard and above support native-client tunneling."
  value       = var.create_bastion ? var.bastion_sku : null
}

output "connection_instructions" {
  description = "Exactly how to get a shell on this VM. There is no SSH-from-the-internet alternative, by design."
  value       = local.connection_instructions
}

output "auto_stop" {
  description = "Effective auto-stop configuration, both layers."
  value = {
    scheduled_shutdown_enabled = var.auto_stop_enabled
    scheduled_shutdown_time    = "${var.auto_stop_time} ${var.auto_stop_timezone}"
    idle_shutdown_enabled      = var.idle_shutdown_enabled
    idle_shutdown_minutes      = var.idle_shutdown_minutes
  }
}
