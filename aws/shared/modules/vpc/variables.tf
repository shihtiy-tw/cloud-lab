variable "project_name" {
  description = "Project or application name; used to name and tag resources."
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

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be large enough for az_count public plus az_count private /24s."
  type        = string
  default     = "10.0.0.0/16"

  # Subnets are carved with 8 extra bits at indexes 0-5 and 8-13, so a prefix
  # that cannot supply index 15 cannot supply this module's layout either.
  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 8, 15))
    error_message = "vpc_cidr must be a valid CIDR of /20 or larger to fit the subnets this module carves."
  }
}

variable "tags" {
  description = "Additional tags merged into (and able to override) the common tag set."
  type        = map(string)
  default     = {}
}

variable "az_count" {
  description = <<-EOT
    Number of availability zones to span. Two is enough for a lab: subnets are
    free, but each extra AZ is another NAT gateway once single_nat_gateway is
    false.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 6
    error_message = "az_count must be between 1 and 6."
  }
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Give the private subnets egress through a NAT gateway. Required for anything
    that has to reach apt, GitHub or a container registry. Turn it off only if
    every private workload can live behind VPC interface endpoints -- see the
    module README.
  EOT
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = <<-EOT
    Route every private subnet through one NAT gateway instead of one per AZ.
    A NAT gateway is ~$32/month before data processing, so per-AZ NAT triples the
    standing cost of a lab VPC to buy AZ-failure isolation nothing here needs.
  EOT
  type        = bool
  default     = true
}

variable "map_public_ip_on_launch" {
  description = <<-EOT
    Auto-assign public IPs to instances launched in the public subnets. Off by
    default: the public subnets exist to hold the NAT gateway, and a default-on
    public IP is exactly the accident this lab's connectivity model forbids.
  EOT
  type        = bool
  default     = false
}
