terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # https://registry.terraform.io/providers/hashicorp/google/latest
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

# No provider block here on purpose.
#
# The project and region belong to whoever calls this module, so callers
# configure the google provider and this module inherits it. Every resource
# below still sets `project` explicitly from var.project_id rather than relying
# on the provider default: a module that silently lands in whatever project
# happened to be configured is the kind of thing you only notice after you have
# created a VPC in production.
