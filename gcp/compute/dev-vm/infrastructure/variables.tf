variable "project_name" {
  description = "Project or application name; used to name and tag resources."
  type        = string

  # Every resource name in this stack is built from this value, and GCP names are
  # RFC 1035: lowercase, dash-separated, starting with a letter. The API rejects
  # anything else at apply time rather than sanitising it, so catch it at plan
  # time instead.
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,40}[a-z0-9]$", var.project_name))
    error_message = "project_name must be lowercase letters, digits and dashes, start with a letter, end alphanumeric, and be at most 42 characters."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "test", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, test, prod."
  }
}

variable "region" {
  description = "Cloud region to deploy into."
  type        = string
  default     = "us-central1"
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

variable "project_id" {
  description = "GCP project id."
  type        = string
}

# ---------------------------------------------------------------------------
# Placement and sizing
# ---------------------------------------------------------------------------

variable "zone" {
  description = <<-EOT
    Zone for the instance and its data disk. Empty means "<region>-a", which keeps
    a single-variable deployment working. It matters that this is one zone and not
    a set: the persistent home disk is zonal, so the VM can only ever come back in
    the zone its disk lives in.
  EOT
  type        = string
  default     = ""
}

variable "machine_type" {
  description = <<-EOT
    Instance machine type. e2-standard-4 (4 vCPU / 16 GB) is the smallest shape
    that builds neovim plugins and runs a kind cluster without swapping. Sizing
    down is fine; the box stops when idle, so the hourly rate matters less than
    the hours.
  EOT
  type        = string
  default     = "e2-standard-4"
}

variable "boot_disk_size" {
  description = "Boot disk size in GB. Holds the OS, the tooling the image installs, and /opt/dev-vm/home-seed."
  type        = number
  default     = 50

  validation {
    condition     = var.boot_disk_size >= 30
    error_message = "boot_disk_size must be at least 30 GB; the image plus the home seed does not fit in less."
  }
}

variable "boot_disk_type" {
  description = "Boot disk type. pd-balanced is the right default: pd-ssd costs more for IOPS a dev box does not need."
  type        = string
  default     = "pd-balanced"
}

variable "data_disk_size" {
  description = "Size in GB of the persistent home disk. This is the disk that survives destroy, so growing it later is easy and shrinking it is not."
  type        = number
  default     = 100

  validation {
    condition     = var.data_disk_size >= 10
    error_message = "data_disk_size must be at least 10 GB."
  }
}

variable "data_disk_type" {
  description = "Type of the persistent home disk."
  type        = string
  default     = "pd-balanced"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "Address plan handed to gcp/shared/modules/network. Only the carved subnetwork range is ever assigned."
  type        = string
  default     = "10.10.0.0/16"
}

variable "enable_cloud_nat" {
  description = <<-EOT
    Create Cloud NAT for egress. On by default because the dotfiles installer
    fetches from apt, GitHub and container registries, none of which
    private_ip_google_access can reach. This is ~$32/month of standing cost and
    the single biggest line item once the VM spends most of its life stopped.
  EOT
  type        = bool
  default     = true
}

variable "iap_source_ranges" {
  description = <<-EOT
    Override the source ranges on the one tcp:22 ingress rule. Leave null: null
    means the network module's default, which is the range Google publishes for
    IAP TCP forwarding, declared once in gcp/shared/modules/network.

    Exposed here only so the value can come from the environment
    (TF_VAR_iap_source_ranges) if Google ever changes the range. The module
    rejects 0.0.0.0/0 and ::/0 regardless of how the value arrives.
  EOT
  type        = list(string)
  default     = null
}

variable "additional_network_tags" {
  description = "Extra network tags for the instance, appended to the IAP tag the firewall rule matches."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Image
# ---------------------------------------------------------------------------

variable "image_family" {
  description = <<-EOT
    Image family published by shared/packer/dev-vm.pkr.hcl. The Packer template
    builds "<image_name>-ubuntu<release>", so the default here has to track
    image_name = "dev-vm" and ubuntu_release = "24.04" on that side.
  EOT
  type        = string
  default     = "dev-vm-ubuntu2404"
}

variable "image_project" {
  description = "Project the image family lives in. Empty means the same project as the VM."
  type        = string
  default     = ""
}

variable "image_id" {
  description = <<-EOT
    Explicit image, as a name or self link, taking precedence over the family
    lookup. Set this to pin the box to one build: a family lookup resolves to
    whatever the newest image is at plan time, so the next Packer build turns into
    an instance replacement in a plan nobody expected to be destructive.
  EOT
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Image contract -- /etc/dev-vm/seed-home.env
# ---------------------------------------------------------------------------

variable "target_user" {
  description = "Login user whose home directory lives on the persistent disk. Must match target_user in the Packer build."
  type        = string
  default     = "ubuntu"
}

variable "home_seed_dir" {
  description = "Where install.sh stashed the pristine home. Must match HOME_SEED_DIR baked into the image."
  type        = string
  default     = "/opt/dev-vm/home-seed"
}

variable "fs_label" {
  description = <<-EOT
    Filesystem label seed-home.sh gives the data disk and later recognises it by.
    Changing this on an existing VM makes the script stop recognising an
    already-seeded disk, so treat it as fixed once a disk exists.
  EOT
  type        = string
  default     = "devhome"
}

# ---------------------------------------------------------------------------
# Image contract -- /etc/dev-vm/idle-shutdown.env
# ---------------------------------------------------------------------------

variable "idle_shutdown_enabled" {
  description = "Let the on-box timer power the VM off when nothing is happening. This is the control that actually keeps the bill small."
  type        = bool
  default     = true
}

variable "idle_minutes" {
  description = "Consecutive idle minutes before shutdown. Recovery is cheap because the home directory is on a persistent disk."
  type        = number
  default     = 30

  validation {
    condition     = var.idle_minutes >= 5
    error_message = "idle_minutes must be at least 5, the check interval."
  }
}

variable "idle_load_threshold" {
  description = "1-minute load average below which the box counts as idle. Above it, something is compiling and must not be killed."
  type        = number
  default     = 0.5
}

variable "idle_ignore_containers" {
  description = "Treat running containers as idle. Off by default: a kind cluster left up is work in progress, not idleness."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Scheduled stop (the backstop for the on-box timer)
# ---------------------------------------------------------------------------

variable "auto_stop_enabled" {
  description = <<-EOT
    Attach an instance schedule policy that stops (and optionally starts) the VM
    on a clock. This is the backstop for the on-box idle timer, which cannot help
    if the box wedges.
  EOT
  type        = bool
  default     = true
}

variable "vm_stop_schedule" {
  description = "Cron expression for the hard stop, in var.schedule_time_zone."
  type        = string
  default     = "0 20 * * *"
}

variable "vm_start_schedule" {
  description = <<-EOT
    Cron expression for an automatic start, or empty for none. Empty is the
    default on purpose: a box that starts itself every weekday morning bills for
    every morning you did not use it, and starting one on demand takes seconds.
  EOT
  type        = string
  default     = ""
}

variable "schedule_time_zone" {
  description = "IANA time zone the schedules are interpreted in. A schedule in the wrong zone stops the box mid-afternoon."
  type        = string
  default     = "Etc/UTC"
}

# ---------------------------------------------------------------------------
# Access
# ---------------------------------------------------------------------------

variable "developer_principals" {
  description = <<-EOT
    IAM principals allowed to reach the VM, in `user:`, `group:` or
    `serviceAccount:` form. These bindings are what actually grant access: with
    no external IP and no metadata SSH keys, an empty list means nobody can log
    in at all.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for p in var.developer_principals :
      can(regex("^(user|group|serviceAccount|domain):", p))
    ])
    error_message = "each developer principal must be prefixed with user:, group:, serviceAccount: or domain:."
  }
}

variable "os_login_admin" {
  description = <<-EOT
    Grant roles/compute.osAdminLogin instead of roles/compute.osLogin, i.e. sudo
    on the box. True by default because this is one person's own dev VM and the
    dotfiles installer needs root; set it false for a shared box where sudo should
    be a deliberate escalation.
  EOT
  type        = bool
  default     = true
}

variable "enable_serial_console" {
  description = <<-EOT
    Enable interactive serial console access. Off by default: the serial console
    is a password-free root path guarded only by IAM, it bypasses OS Login
    entirely, and it does not honour the firewall. Turn it on for the length of a
    recovery and turn it back off -- see the recovery section of the README.
  EOT
  type        = bool
  default     = false
}
