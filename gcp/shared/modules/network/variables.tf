variable "project_id" {
  description = "GCP project id to create the network in."
  type        = string
}

variable "project_name" {
  description = "Project or application name; used to name resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "test", "prod", "sandbox", "demo"], var.environment)
    error_message = "environment must be one of: dev, staging, test, prod, sandbox, demo."
  }
}

variable "region" {
  description = "Region for the subnetwork, Cloud Router and Cloud NAT."
  type        = string
  default     = "us-central1"
}

variable "vpc_cidr" {
  description = <<-EOT
    Address plan the subnetwork is carved from. A GCP network has no CIDR of its
    own -- only subnetworks carry ranges -- so this is a planning range, not a
    property of any resource. Kept as an input for parity with
    aws/shared/modules/vpc so the interface reads the same on both clouds.
  EOT
  type        = string
  default     = "10.10.0.0/16"

  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 8, 0))
    error_message = "vpc_cidr must be a valid CIDR of /24 or larger."
  }
}

variable "subnet_newbits" {
  description = <<-EOT
    Extra prefix bits used to carve the subnetwork out of vpc_cidr. The default
    leaves the rest of vpc_cidr free for later subnets (GKE secondary ranges, a
    proxy-only subnet for a load balancer) instead of consuming the whole plan
    on one dev VM.
  EOT
  type        = number
  default     = 8

  validation {
    condition     = var.subnet_newbits >= 0 && var.subnet_newbits <= 16
    error_message = "subnet_newbits must be between 0 and 16."
  }
}

variable "labels" {
  description = <<-EOT
    Ownership labels for the caller's resources. None of the resources in this
    module accept labels -- see the note in main.tf -- so they are folded into
    resource descriptions instead of being dropped.
  EOT
  type        = map(string)
  default     = {}
}

variable "iap_target_tags" {
  description = <<-EOT
    Network tags the IAP SSH rule applies to. Scoping by tag rather than opening
    the rule to every instance in the network means a future VM has to opt in to
    being reachable, which is the safer default when the rule's whole job is to
    be the one ingress path.
  EOT
  type        = list(string)
  default     = ["iap-ssh"]

  validation {
    condition     = length(var.iap_target_tags) > 0
    error_message = "iap_target_tags must not be empty; an untargeted rule would apply to every instance in the network."
  }
}

variable "enable_cloud_nat" {
  description = <<-EOT
    Give the subnetwork egress through Cloud NAT. Required for anything that has
    to reach apt, GitHub or a container registry: private_ip_google_access covers
    Google APIs only. Cloud NAT is ~$32/month of standing cost and becomes the
    dominant line item once the VM auto-stops, so it is a variable rather than a
    fact -- turn it off for a box that only ever talks to Google APIs.
  EOT
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs on the subnetwork. This is the only record of what a private VM talked to."
  type        = bool
  default     = true
}

variable "flow_log_sampling" {
  description = <<-EOT
    Fraction of flows sampled, 0.0 to 1.0. Flow logs are billed per GB ingested;
    half of the flows from a single-VM subnet is plenty to answer "what did this
    box connect to?" without paying for full capture.
  EOT
  type        = number
  default     = 0.5

  validation {
    condition     = var.flow_log_sampling > 0 && var.flow_log_sampling <= 1
    error_message = "flow_log_sampling must be greater than 0 and at most 1."
  }
}
