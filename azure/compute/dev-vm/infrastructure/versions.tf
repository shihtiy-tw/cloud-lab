terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # https://registry.terraform.io/providers/hashicorp/azurerm/latest
    #
    # >= 4.0, not >= 3.0. This stack uses two things older providers do not have:
    # `default_outbound_access_enabled` on the subnet (via the network module) and
    # the Developer Bastion SKU, which needs `virtual_network_id` on
    # azurerm_bastion_host and the ability to omit `ip_configuration` entirely.
    # Verified against azurerm 5.1.0, whose own validation reads
    # "`virtual_network_id` is required when `sku` is `Developer`".
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}
