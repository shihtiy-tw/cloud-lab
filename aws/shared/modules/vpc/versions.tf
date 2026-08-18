terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # https://registry.terraform.io/providers/hashicorp/aws/latest
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# No provider block here on purpose.
#
# The region belongs to whoever calls this module, so callers configure the aws
# provider and this module inherits it. aws/compute/ecs/infrastructure/vpc does
# the opposite -- `provider "aws" { region = terraform.workspace }` -- which ties
# the region to the workspace name and is why `--env dev` cannot select a
# workspace anywhere in this repo. Do not reintroduce it: a workspace names an
# environment, not a region.
#
# Running this directory directly (as aws/tests/vpc_test.go does) therefore picks
# the region up from AWS_REGION / AWS_DEFAULT_REGION, which is what Terratest
# already exports.
