# azure/shared/modules/network

VNet for a workload that must reach out but never be reached: one workload subnet
with **no default outbound access**, a NAT Gateway for egress, and an NSG whose
only inbound allowance is VNet-scoped SSH so Azure Bastion can land a session.

`azure/compute/dev-vm` is the caller this was written for.

## What it creates

| Resource | Notes |
|----------|-------|
| `azurerm_resource_group` | Only when `create_resource_group = true`. Default is to adopt an existing group by name. |
| `azurerm_virtual_network` | `address_space = [var.vnet_cidr]`. |
| `azurerm_subnet` (workload) | `default_outbound_access_enabled = false`. |
| `azurerm_public_ip` + `azurerm_nat_gateway` + 2 associations | The subnet's only route to the internet, outbound only. |
| `azurerm_network_security_group` + 2 rules | `AllowBastionSshInbound` (VNet-scoped, 22) and `DenyAllInbound` (4096). |
| `azurerm_subnet` (`AzureBastionSubnet`) | Only when `create_bastion_subnet = true`, i.e. the Basic/Standard Bastion path. |

## Two decisions worth knowing before you change anything

**Default outbound access is set explicitly, not left to the provider.** Azure has
retired the implicit platform SNAT that used to give any VM internet access for
free. Subnets created via API versions after 2026-03-31 get none of it. Leaving
the attribute unset would make "does `apt update` work?" depend on which azurerm
release is installed, so it is pinned to `false` and egress is provided
deliberately by the NAT Gateway. A subnet with neither is a VM that cannot reach
apt, GitHub, or the dotfiles repository — and that failure looks like DNS.

**The NAT Gateway's public IP is not the VM's public IP.** They are different
resources with opposite meanings. A public IP on a NAT Gateway is an outbound
source address and accepts nothing inbound. A public IP on a NIC is exactly what
this design refuses to have. If you find yourself adding
`public_ip_address_id` to an `ip_configuration`, you are on the wrong resource.

## Inputs

| Name | Type | Default | Purpose |
|------|------|---------|---------|
| `project_name` | string | — | Naming and tagging. |
| `environment` | string | — | One of `dev`, `staging`, `test`, `prod`. |
| `location` | string | `eastus` | Azure region. Named `location`, not `region`. |
| `resource_group_name` | string | — | Existing group to use, or the name of the group to create. |
| `create_resource_group` | bool | `false` | Create rather than adopt. |
| `vnet_cidr` | string | `10.30.0.0/16` | VNet address space. |
| `subnet_cidr` | string | `""` | Workload prefix; empty derives a /24 from the front of `vnet_cidr`. |
| `create_bastion_subnet` | bool | `false` | Create `AzureBastionSubnet` (Basic/Standard SKU only). |
| `bastion_subnet_cidr` | string | `""` | Empty derives a /26 from the top of `vnet_cidr`. Azure rejects anything smaller than /26. |
| `bastion_ssh_source_address_prefix` | string | `VirtualNetwork` | Inbound SSH scope. Validation rejects internet-wide values. |
| `nat_gateway_idle_timeout_in_minutes` | number | `4` | SNAT flow idle timeout. |
| `tags` | map(string) | `{}` | Merged last, so it can override any computed tag. |

`subnet_cidr` and `bastion_subnet_cidr` are derived with `cidrsubnet(vnet_cidr,
8, 0)` and `cidrsubnet(vnet_cidr, 10, 1023)`, which assume `vnet_cidr` is /16 or
larger. Pass both explicitly for a smaller space.

## Outputs

`resource_group_name`, `vnet_id`, `vnet_name`, `subnet_id`, `subnet_name`,
`subnet_cidr`, `nat_gateway_id`, `nat_public_ip_address`,
`network_security_group_id`, `network_security_group_name`, `bastion_subnet_id`,
`inbound_security_rules`.

`inbound_security_rules` exists so a test can assert "no inbound rule has an
internet-wide source" against outputs instead of parsing a plan.

## Cost

The NAT Gateway is the only standing charge: roughly **$0.045/hour (~$32/month)**
plus **$0.045 per GB processed**, and it keeps billing while the VM is stopped. The
public IP adds a few dollars a month. Everything else here (VNet, subnets, NSG,
rules) is free.

## Validate

```bash
terraform -chdir=azure/shared/modules/network init -backend=false -input=false
terraform -chdir=azure/shared/modules/network validate
```

Both work with no Azure credentials.
