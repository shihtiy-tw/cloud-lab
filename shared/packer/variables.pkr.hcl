// Inputs for the dev-vm golden image build.
//
// Cross-cloud values come first, then per-cloud blocks. Every cloud-specific
// variable is optional so `packer build -only=amazon-ebs.*` works without
// supplying GCP or Azure settings.

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------

variable "image_name" {
  type        = string
  default     = "dev-vm"
  description = "Base name for the produced image."
}

variable "image_version" {
  type        = string
  default     = "0.1.0"
  description = <<-EOT
    Semantic version for this image. Azure Compute Gallery requires
    MAJOR.MINOR.PATCH, so keep that shape for all clouds to stay consistent.
  EOT

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_version))
    error_message = "The image_version must be MAJOR.MINOR.PATCH, which Azure Compute Gallery requires."
  }
}

variable "ubuntu_release" {
  type        = string
  default     = "24.04"
  description = <<-EOT
    Ubuntu LTS release to build from.

    Defaults to 24.04 rather than the newer 26.04 on purpose. 26.04 LTS
    ("Resolute Raccoon") shipped 2026-04-23, and third-party apt repositories
    (Docker, HashiCorp, Kubernetes) routinely lag a new release by months. The
    dotfiles installer depends on those repositories, so building on 26.04 before
    they publish a `resolute` pocket fails partway through. Flip this to "26.04"
    once they have; the whole point of a Packer pipeline is that trying it costs
    one build, not a broken VM.
  EOT

  validation {
    condition     = contains(["24.04", "26.04"], var.ubuntu_release)
    error_message = "The ubuntu_release must be either 24.04 or 26.04, both of which are LTS."
  }
}

variable "architecture" {
  type        = string
  default     = "amd64"
  description = <<-EOT
    Target CPU architecture. arm64 (Graviton / Axion / Cobalt) is 20-40% cheaper,
    but some tools the dotfiles installer fetches publish amd64-only release
    assets, so amd64 is the safe default until an arm64 build has been proven.
  EOT

  validation {
    condition     = contains(["amd64", "arm64"], var.architecture)
    error_message = "The architecture must be either amd64 or arm64."
  }
}

variable "target_user" {
  type        = string
  default     = "ubuntu"
  description = "User that owns the development environment."
}

variable "dotfiles_repo" {
  type        = string
  default     = "https://github.com/shihtiy-tw/dotfiles.git"
  description = "Dotfiles repository to bake in."
}

variable "dotfiles_ref" {
  type        = string
  default     = "develop"
  description = <<-EOT
    Git ref to check out. Prefer a commit SHA: "develop" is a moving target, so
    two builds a week apart produce different images from identical inputs. The
    resolved SHA is always recorded in /etc/dev-vm-build.json on the image.
  EOT
}

variable "dotfiles_extras" {
  type        = string
  default     = "cloud"
  description = <<-EOT
    Space-separated extra make targets. Upstream's "cloud" target is
    aws + gcp + azure + kubernetes, which brings in the session-manager-plugin,
    the GKE auth plugin, kubelogin, and kubectl/helm/k9s/kustomize -- exactly the
    toolchain the three brokered access paths need.
  EOT
}

variable "root_volume_size" {
  type        = number
  default     = 50
  description = <<-EOT
    OS disk size in GB. 30 is the usual default and is too small here: neovim's
    mason LSP servers, Docker images, and the Kubernetes toolchain together run
    well past it.
  EOT

  validation {
    condition     = var.root_volume_size >= 30
    error_message = "The root_volume_size must be at least 30 GB."
  }
}

// ---------------------------------------------------------------------------
// AWS
// ---------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Region to build the AMI in."
}

variable "aws_instance_type" {
  type        = string
  default     = ""
  description = "Build instance type. Empty selects a default based on architecture."
}

variable "aws_subnet_id" {
  type        = string
  default     = ""
  description = <<-EOT
    Private subnet for the build instance. Required, because the build connects
    over SSM rather than SSH and therefore never gets a public IP. The subnet
    needs egress (NAT gateway or SSM VPC endpoints) so the agent can reach
    Systems Manager.
  EOT
}

variable "aws_iam_instance_profile" {
  type        = string
  default     = ""
  description = <<-EOT
    Instance profile granting AmazonSSMManagedInstanceCore. Without it the SSM
    agent cannot register and `ssh_interface = "session_manager"` never connects.
  EOT
}

variable "aws_ami_users" {
  type        = list(string)
  default     = []
  description = "Extra account IDs to share the AMI with."
}

// ---------------------------------------------------------------------------
// GCP
// ---------------------------------------------------------------------------

variable "gcp_project_id" {
  type        = string
  default     = ""
  description = "GCP project to build in."
}

variable "gcp_zone" {
  type        = string
  default     = "us-central1-a"
  description = "Zone for the build instance."
}

variable "gcp_machine_type" {
  type        = string
  default     = ""
  description = "Build machine type. Empty selects a default based on architecture."
}

variable "gcp_subnetwork" {
  type        = string
  default     = ""
  description = <<-EOT
    Subnetwork for the build instance. Needs Cloud NAT for egress and a firewall
    rule allowing 35.235.240.0/20 on port 22, since the build connects through
    IAP with no external IP.
  EOT
}

variable "gcp_service_account_email" {
  type        = string
  default     = ""
  description = "Service account for the build instance."
}

// ---------------------------------------------------------------------------
// Azure
// ---------------------------------------------------------------------------

variable "azure_subscription_id" {
  type        = string
  default     = ""
  description = "Azure subscription to build in."
}

variable "azure_location" {
  type        = string
  default     = "eastus"
  description = "Region to build in. Must match the Compute Gallery's region."
}

variable "azure_vm_size" {
  type        = string
  default     = ""
  description = "Build VM size. Empty selects a default based on architecture."
}

variable "azure_build_resource_group" {
  type        = string
  default     = ""
  description = "Resource group for transient build resources. Empty lets Packer create one."
}

variable "azure_gallery_resource_group" {
  type        = string
  default     = "cloud-lab-images"
  description = <<-EOT
    Resource group holding the Compute Gallery to publish into.

    Non-empty by default because the azure-arm plugin reads an empty string as
    "no gallery destination configured" and fails validation, which would make
    `packer validate` impossible to run without credentials.
  EOT
}

variable "azure_gallery_name" {
  type        = string
  default     = "cloudlab"
  description = "Compute Gallery (Shared Image Gallery) name. Galleries allow only alphanumerics, dots and underscores."
}

variable "azure_gallery_image_name" {
  type        = string
  default     = "dev-vm"
  description = "Image definition name inside the gallery."
}

variable "azure_gallery_replication_regions" {
  type        = list(string)
  default     = []
  description = "Regions to replicate the gallery image version to."
}

variable "azure_build_subnet_id" {
  type        = string
  default     = ""
  description = <<-EOT
    Optional existing subnet for the build VM.

    Azure is the one cloud that cannot do a fully private Packer build from a
    workstation: setting virtual_network_name means Packer must itself run from a
    host inside that VNet. When this is empty, Packer creates a temporary VNet and
    gives the *build* VM an ephemeral public IP locked down by
    azure_build_allowed_cidr. That is acceptable because the build VM is
    short-lived and holds no data -- the dev VM created by Terraform never gets a
    public IP. Set this (and run Packer from inside the VNet) to close even that
    gap.
  EOT
}

variable "azure_build_allowed_cidr" {
  type        = string
  default     = ""
  description = <<-EOT
    CIDR permitted to reach the build VM, ideally your egress /32. Leaving this
    empty means Azure's default of allowing any source, which defeats the point;
    the build fails fast instead.
  EOT
}
