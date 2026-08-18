provider "azurerm" {
  # Null rather than "" so azurerm falls back to ARM_SUBSCRIPTION_ID or the az
  # CLI's current subscription. An empty string is a value, and azurerm 4.x+
  # rejects it.
  subscription_id = var.subscription_id != "" ? var.subscription_id : null

  features {
    virtual_machine {
      # Delete the OS disk with the VM. The OS disk is disposable here -- it is a
      # copy of a gallery image and holds no state worth keeping. The disk that
      # matters is the data disk, which is a separate resource carrying
      # prevent_destroy.
      delete_os_disk_on_deletion = true

      # Shut the guest down cleanly before deallocating so the ext4 home
      # filesystem is not torn away mid-write.
      skip_shutdown_and_force_delete = false
    }

    resource_group {
      # Refuse to delete a resource group that still contains resources. In a
      # shared subscription this stack may not be the only tenant of its group,
      # and the default behaviour would take the neighbours with it.
      prevent_deletion_if_contains_resources = true
    }
  }
}
