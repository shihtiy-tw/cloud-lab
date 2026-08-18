# The contract with the shared image.
#
# The image (shared/packer/dev-vm.pkr.hcl) bakes ~/dotfiles into the user's home
# and stashes a pristine copy at HOME_SEED_DIR, outside the mount point. The data
# volume then mounts *over* that home directory, which would hide everything the
# image installed -- so shared/bootstrap/seed-home.sh restores the stashed copy
# the first time it finds the volume unseeded, and leaves it alone forever after.
# That is what makes the disk persistent rather than merely re-imaged.
#
# Terraform's job is only to tell those scripts where the disk is and how
# aggressively to power the box off. Both are env files under /etc/dev-vm/; see
# shared/README.md, "The home-seeding contract".

locals {
  user_data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
    target_user   = var.target_user
    home_seed_dir = "/opt/dev-vm/home-seed"
    fs_label      = "devhome"

    # /dev/sdf as requested by the volume attachment, as the guest sees it. See
    # var.data_disk_device for the Nitro vs Xen difference.
    data_disk_device = var.data_disk_device

    # Booleans have to reach the file as the literal strings the shell scripts
    # compare against ("true"/"false"), not as HCL bools.
    idle_enabled           = var.idle_shutdown_enabled ? "true" : "false"
    idle_ignore_containers = var.idle_ignore_containers ? "true" : "false"
    idle_minutes           = var.idle_minutes
    idle_load_threshold    = var.idle_load_threshold

    region = var.region
  })
}
