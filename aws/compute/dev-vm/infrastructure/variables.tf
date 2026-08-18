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

variable "region" {
  description = "Cloud region to deploy into."
  type        = string
  default     = "us-east-1"
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

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC this stack creates."
  type        = string
  default     = "10.30.0.0/16"
}

variable "az_count" {
  description = "AZs the VPC spans. The VM itself lives in the first one, because its persistent EBS home is zonal."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway across all private subnets. See the README cost section before turning this off."
  type        = bool
  default     = true
}

variable "egress_cidr_blocks" {
  description = <<-EOT
    Destinations the VM may reach outbound. This is the only direction traffic
    ever flows, so it is the only rule the security group has.

    Wide open by default, and that is a considered choice rather than laziness:
    SSM needs 443 to the regional endpoints, apt and GitHub need 80 and 443,
    and DNS needs UDP 53 to the VPC resolver -- security group egress rules apply
    to that too, so a naive "443 only" lockdown produces a box that cannot
    resolve anything. Narrow this to a proxy CIDR when there is a proxy to point
    at.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# Image
# ---------------------------------------------------------------------------

variable "ami_id" {
  description = <<-EOT
    AMI to launch, taking precedence over the lookup below when set. Prefer
    setting it: `shared/packer/manifest.json` records the exact id every build
    produced, and a pinned id is the difference between a plan you can read and
    a plan that replaces your VM because someone rebuilt the image.
  EOT
  type        = string
  default     = ""
}

variable "ami_name_prefix" {
  description = "Name prefix the Packer build stamps on the AMI (see local.image_name in shared/packer/dev-vm.pkr.hcl)."
  type        = string
  default     = "dev-vm"
}

variable "ami_owners" {
  description = "Accounts trusted to own the AMI. Never leave this unset: an unowned name filter can match someone else's lookalike image."
  type        = list(string)
  default     = ["self"]
}

variable "ami_image_version" {
  description = "Value of the image_version tag to select, matching the Packer variable of the same name. This is the pin; empty means 'newest match', which is not one."
  type        = string
  default     = "0.1.0"
}

variable "ubuntu_release" {
  description = "Ubuntu release baked into the image, used to build the AMI name filter."
  type        = string
  default     = "24.04"
}

variable "architecture" {
  description = "Image architecture, used to build the AMI name filter. Must agree with instance_type."
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.architecture)
    error_message = "architecture must be either amd64 or arm64."
  }
}

# ---------------------------------------------------------------------------
# Instance
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = <<-EOT
    Instance type for the VM. t3.large is the smallest size where a neovim
    plugin build and a kind cluster coexist without swapping; drop to t3.medium
    if the box is only ever an editor and a shell.
  EOT
  type        = string
  default     = "t3.large"
}

variable "target_user" {
  description = "The user whose home the image baked and whose home the data volume becomes. Must match the Packer target_user."
  type        = string
  default     = "ubuntu"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB. The image is built at 50; smaller than the image is rejected by EC2."
  type        = number
  default     = 50
}

variable "data_volume_size" {
  description = "Persistent home volume size in GB. This is the disk that survives destroy, so it is the one worth sizing generously."
  type        = number
  default     = 100
}

variable "data_disk_device" {
  description = <<-EOT
    Device path the data volume appears at inside the VM, written to
    /etc/dev-vm/seed-home.env for shared/bootstrap/seed-home.sh.

    /dev/nvme1n1 is correct for Nitro instance types (t3, m5, c6i, anything
    current). Xen generations (t2, m4) present the same volume as /dev/xvdf.
    Terraform always requests /dev/sdf; the guest naming is the hypervisor's
    choice, not ours.
  EOT
  type        = string
  default     = "/dev/nvme1n1"
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for EBS and log encryption. Empty uses the AWS-managed aws/ebs and aws/logs keys, which are still encryption at rest -- a CMK buys key rotation control and cross-account grants, not more encryption."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Idle shutdown (on-box, /etc/dev-vm/idle-shutdown.env)
# ---------------------------------------------------------------------------

variable "idle_shutdown_enabled" {
  description = "Let the on-box timer power the VM off when nobody is using it."
  type        = bool
  default     = true
}

variable "idle_minutes" {
  description = "Consecutive idle minutes before the on-box timer powers off. Must be a multiple of 5, the timer's interval."
  type        = number
  default     = 30

  validation {
    condition     = var.idle_minutes >= 5 && var.idle_minutes % 5 == 0
    error_message = "idle_minutes must be at least 5 and a multiple of the 5 minute check interval."
  }
}

variable "idle_load_threshold" {
  description = "1-minute load average above which the box counts as busy even with no session attached."
  type        = number
  default     = 0.5
}

variable "idle_ignore_containers" {
  description = "Treat running containers as idle. Leave false unless a permanently running container keeps the VM alive forever."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Auto-stop (EventBridge Scheduler backstop)
# ---------------------------------------------------------------------------

variable "auto_stop_enabled" {
  description = "Enable the scheduled hard stop. The on-box idle timer cannot save you if the box wedges; this can."
  type        = bool
  default     = true
}

variable "auto_stop_cron" {
  description = "EventBridge Scheduler expression for the hard stop. cron() and rate() are both accepted."
  type        = string
  default     = "cron(0 21 ? * MON-FRI *)"
}

variable "auto_stop_timezone" {
  description = "Timezone the schedule is evaluated in. An IANA name, not an offset, so daylight saving is handled for you."
  type        = string
  default     = "Etc/UTC"
}

# ---------------------------------------------------------------------------
# Session logging
# ---------------------------------------------------------------------------

variable "session_log_retention_days" {
  description = "Retention for the Session Manager log group. Zero means never expire."
  type        = number
  default     = 30
}

variable "enable_session_log_bucket" {
  description = "Also stream session transcripts to S3. CloudWatch is enough to answer 'what happened in that session'; S3 is for keeping transcripts longer than the log group, cheaply."
  type        = bool
  default     = false
}

variable "session_idle_timeout_minutes" {
  description = "Idle minutes before Session Manager closes a session. Bounded to 1-60 by the service."
  type        = number
  default     = 20

  validation {
    condition     = var.session_idle_timeout_minutes >= 1 && var.session_idle_timeout_minutes <= 60
    error_message = "session_idle_timeout_minutes must be between 1 and 60."
  }
}

variable "session_max_duration_minutes" {
  description = "Hard cap on a single session, 60-1440 minutes. A forgotten session is a running VM."
  type        = number
  default     = 720

  validation {
    condition     = var.session_max_duration_minutes >= 60 && var.session_max_duration_minutes <= 1440
    error_message = "session_max_duration_minutes must be between 60 and 1440."
  }
}
