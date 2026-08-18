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
