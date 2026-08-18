# The region comes from a variable, not from terraform.workspace.
#
# aws/compute/ecs/infrastructure/vpc pins `region = terraform.workspace`, which
# conflates two unrelated things: a workspace names an environment (dev, staging),
# a region names a location. That coupling is why `--env dev` cannot select a
# workspace anywhere in this repo. Do not reintroduce it here.
provider "aws" {
  region = var.region
}
