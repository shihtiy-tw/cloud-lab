terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # https://registry.terraform.io/providers/hashicorp/azurerm/latest
    #
    # >= 4.0 rather than >= 3.0 because this module sets
    # `default_outbound_access_enabled` on the subnet, which only exists in
    # recent provider releases. A constraint that resolves to a provider without
    # that attribute would fail with a confusing "unsupported argument" error
    # instead of a version error.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}

# No provider block here on purpose.
#
# The subscription and tenant belong to whoever calls this module, so callers
# configure the azurerm provider and this module inherits it. That also means
# `terraform validate` works in this directory with no credentials: the provider
# schema is enough to check the configuration.
