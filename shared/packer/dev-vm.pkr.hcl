// Golden image for the multi-cloud dotfiles development VM.
//
// One template, three sources, one provisioner. The provisioner is
// shared/bootstrap/install.sh, which is deliberately cloud-agnostic, so the only
// difference between clouds is how Packer connects to the build instance.
//
// The connection story is the whole point of this file. The requirement is that
// no SSH port is ever exposed to the internet, which applies to build instances
// as much as to the dev VM:
//
//   amazon-ebs      ssh_interface = "session_manager" -- Packer tunnels SSH
//                   through SSM, so the builder needs no public IP and no
//                   security group ingress at all.
//
//   googlecompute   use_iap + omit_external_ip + use_internal_ip -- Packer
//                   tunnels through IAP. Requires the IAP API enabled and gcloud
//                   on the machine running Packer.
//
//   azure-arm       The exception. Azure's virtual_network_name option requires
//                   Packer itself to run from a host inside that VNet, so a
//                   laptop-driven private build is impossible. The build VM gets
//                   an ephemeral public IP restricted to azure_build_allowed_cidr
//                   and is destroyed minutes later. The dev VM that Terraform
//                   creates never has a public IP, which is the actual
//                   requirement.
//
// Usage:
//   packer init .
//   packer validate -only='dev-vm.amazon-ebs.dev-vm' .
//   packer build    -only='dev-vm.amazon-ebs.dev-vm' -var-file=aws.pkrvars.hcl .
//
// All three sources validate with no credentials, except that the GCP source
// needs a project id because there is no defensible default for one:
//
//   packer validate -only='dev-vm.googlecompute.dev-vm' -var gcp_project_id=validate-only .

packer {
  required_version = ">= 1.9.0"

  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.2.8"
    }
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = ">= 1.1.4"
    }
    azure = {
      source  = "github.com/hashicorp/azure"
      version = ">= 2.1.2"
    }
  }
}

locals {
  // A single timestamp so every artifact from one run shares a name.
  build_time = formatdate("YYYYMMDD-hhmmss", timestamp())
  image_name = "${var.image_name}-ubuntu${replace(var.ubuntu_release, ".", "")}-${var.architecture}-${var.image_version}"

  // Ubuntu publishes different source image naming per cloud, so map the release
  // to each cloud's identifiers rather than sprinkling conditionals below.
  ubuntu_codename = {
    "24.04" = "noble"
    "26.04" = "resolute"
  }[var.ubuntu_release]

  // Azure marketplace SKUs are "<major><minor>-lts-gen2", plus an arm64 variant.
  azure_sku = var.architecture == "arm64" ? "${replace(var.ubuntu_release, ".", "_")}-lts-arm64" : "${replace(var.ubuntu_release, ".", "_")}-lts-gen2"

  // Sensible per-architecture build sizes, overridable per cloud.
  aws_instance_type = var.aws_instance_type != "" ? var.aws_instance_type : (var.architecture == "arm64" ? "t4g.medium" : "t3.medium")
  gcp_machine_type  = var.gcp_machine_type != "" ? var.gcp_machine_type : (var.architecture == "arm64" ? "t2a-standard-2" : "e2-standard-2")
  azure_vm_size     = var.azure_vm_size != "" ? var.azure_vm_size : (var.architecture == "arm64" ? "Standard_D2ps_v5" : "Standard_D2s_v5")

  // Applied to the image itself so "what is in this image?" is answerable from
  // the console without booting anything.
  image_labels = {
    project        = "cloud-lab"
    component      = "dev-vm"
    managed_by     = "packer"
    ubuntu_release = var.ubuntu_release
    architecture   = var.architecture
    image_version  = var.image_version
    dotfiles_ref   = var.dotfiles_ref
  }

  // GCP label values are restricted to ^[\p{Ll}0-9_-]{0,63}$ -- lowercase
  // letters, digits, dashes and underscores only. Version strings like "24.04"
  // and "0.1.0" contain dots and are rejected outright, so sanitise rather than
  // maintain a second hand-written map.
  gcp_image_labels = {
    for key, value in local.image_labels :
    key => substr(lower(replace(replace(value, ".", "-"), "/", "-")), 0, 63)
  }

  // Environment handed to the provisioner. Identical for all three clouds.
  provisioner_env = [
    "TARGET_USER=${var.target_user}",
    "DOTFILES_REPO=${var.dotfiles_repo}",
    "DOTFILES_REF=${var.dotfiles_ref}",
    "DOTFILES_EXTRAS=${var.dotfiles_extras}",
    "HOME_SEED_DIR=/opt/dev-vm/home-seed",
  ]
}

// ---------------------------------------------------------------------------
// AWS -- builds over SSM Session Manager, no public IP, no ingress rules
// ---------------------------------------------------------------------------

source "amazon-ebs" "dev-vm" {
  region        = var.aws_region
  instance_type = local.aws_instance_type
  ami_name      = "${local.image_name}-${local.build_time}"
  ami_users     = var.aws_ami_users

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd*/ubuntu-${local.ubuntu_codename}-${var.ubuntu_release}-${var.architecture}-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    // Canonical's account. Pinning the owner matters: an unowned name filter can
    // match someone else's lookalike AMI.
    owners      = ["099720109477"]
    most_recent = true
  }

  ssh_username = var.target_user

  // The build instance is unreachable from the internet: Packer opens an SSM
  // tunnel instead, so no public IP and no inbound security group rule exist.
  communicator                = "ssh"
  ssh_interface               = "session_manager"
  iam_instance_profile        = var.aws_iam_instance_profile
  subnet_id                   = var.aws_subnet_id
  associate_public_ip_address = false

  // session_manager connectivity is impossible without an instance profile that
  // can register with SSM. Rather than make callers pre-create one, Packer builds
  // a temporary profile and deletes it with the rest of the build resources. The
  // statement below is the minimum subset of AmazonSSMManagedInstanceCore needed
  // to open a session -- notably it grants no s3:GetObject, so this profile
  // cannot be used to read arbitrary buckets during a build.
  dynamic "temporary_iam_instance_profile_policy_document" {
    for_each = var.aws_iam_instance_profile == "" ? [1] : []

    content {
      Version = "2012-10-17"

      Statement {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = ["*"]
      }
    }
  }

  // Enforce IMDSv2 on the builder too, so a compromised build script cannot use
  // the simpler IMDSv1 request to lift the instance role's credentials.
  imds_support = "v2.0"
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(local.image_labels, {
    Name = local.image_name
  })
  run_tags = merge(local.image_labels, {
    Name = "packer-${local.image_name}"
  })
  snapshot_tags = local.image_labels
}

// ---------------------------------------------------------------------------
// GCP -- builds over IAP TCP forwarding, no external IP
// ---------------------------------------------------------------------------

source "googlecompute" "dev-vm" {
  project_id   = var.gcp_project_id
  zone         = var.gcp_zone
  machine_type = local.gcp_machine_type

  source_image_family     = "ubuntu-${replace(var.ubuntu_release, ".", "")}-lts${var.architecture == "arm64" ? "-arm64" : ""}"
  source_image_project_id = ["ubuntu-os-cloud"]

  image_name        = "${replace(local.image_name, ".", "-")}-${local.build_time}"
  image_family      = "${var.image_name}-ubuntu${replace(var.ubuntu_release, ".", "")}"
  image_description = "dotfiles dev VM, Ubuntu ${var.ubuntu_release} ${var.architecture}, dotfiles ${var.dotfiles_ref}"
  image_labels      = local.gcp_image_labels

  ssh_username = var.target_user

  // No external IP; Packer reaches the builder through an IAP tunnel. This needs
  // the IAP API enabled, gcloud available to Packer, and a firewall rule allowing
  // 35.235.240.0/20 on port 22 in the build subnetwork.
  use_iap          = true
  omit_external_ip = true
  use_internal_ip  = true

  subnetwork            = var.gcp_subnetwork
  service_account_email = var.gcp_service_account_email
  // IAP-based builds still need a token to call the API.
  scopes = ["https://www.googleapis.com/auth/cloud-platform"]

  disk_size = var.root_volume_size
  disk_type = "pd-balanced"

  // Shielded VM protections; cheap and on by default for Ubuntu images anyway.
  enable_secure_boot = true
  enable_vtpm        = true
}

// ---------------------------------------------------------------------------
// Azure -- publishes into a Compute Gallery
// ---------------------------------------------------------------------------

source "azure-arm" "dev-vm" {
  subscription_id = var.azure_subscription_id
  location        = var.azure_location
  vm_size         = local.azure_vm_size

  os_type         = "Linux"
  image_publisher = "canonical"
  image_offer     = "ubuntu-${replace(var.ubuntu_release, ".", "_")}-lts"
  image_sku       = local.azure_sku

  ssh_username = var.target_user

  // Managed image is not created; the artifact is a gallery image version, which
  // is what gives us versioning and replication.
  shared_image_gallery_destination {
    subscription         = var.azure_subscription_id
    resource_group       = var.azure_gallery_resource_group
    gallery_name         = var.azure_gallery_name
    image_name           = var.azure_gallery_image_name
    image_version        = var.image_version
    replication_regions  = length(var.azure_gallery_replication_regions) > 0 ? var.azure_gallery_replication_regions : [var.azure_location]
    storage_account_type = "Standard_LRS"
  }

  build_resource_group_name = var.azure_build_resource_group != "" ? var.azure_build_resource_group : null

  // See the header comment: a private Azure build requires Packer to run inside
  // the VNet. When no subnet is supplied, Packer creates a temporary network and
  // the build VM gets a public IP -- restricted to azure_build_allowed_cidr, and
  // destroyed with the rest of the build resources.
  virtual_network_subnet_name  = var.azure_build_subnet_id != "" ? var.azure_build_subnet_id : null
  allowed_inbound_ip_addresses = var.azure_build_allowed_cidr != "" ? [var.azure_build_allowed_cidr] : []

  os_disk_size_gb = var.root_volume_size

  azure_tags = local.image_labels
}

// ---------------------------------------------------------------------------
// Build -- identical for all three clouds
// ---------------------------------------------------------------------------

build {
  name = "dev-vm"

  sources = [
    "source.amazon-ebs.dev-vm",
    "source.googlecompute.dev-vm",
    "source.azure-arm.dev-vm",
  ]

  // Upload the whole bootstrap directory: install.sh installs its two companion
  // scripts and the systemd units from paths relative to itself.
  provisioner "file" {
    source      = "${path.root}/../bootstrap"
    destination = "/tmp/bootstrap"
  }

  provisioner "shell" {
    inline = ["chmod +x /tmp/bootstrap/*.sh"]
  }

  provisioner "shell" {
    // -E preserves the environment below; install.sh must run as root but does
    // the dotfiles work as ${var.target_user}.
    execute_command  = "chmod +x {{ .Path }}; sudo -E bash -c '{{ .Vars }} {{ .Path }}'"
    environment_vars = local.provisioner_env
    script           = "${path.root}/../bootstrap/install.sh"
    // The dotfiles install compiles neovim plugins and pulls container images;
    // 10 minutes is not enough.
    timeout = "45m"
  }

  // Generalisation. Azure requires deprovisioning; the others just need the
  // build's own traces removed so the image is not born with a machine identity.
  provisioner "shell" {
    only           = ["azure-arm.dev-vm"]
    inline_shebang = "/bin/sh -x"
    skip_clean     = true
    inline = [
      "/usr/sbin/waagent -force -deprovision+user",
      "rm -rf /tmp/bootstrap",
      "sync",
    ]
  }

  provisioner "shell" {
    except = ["azure-arm.dev-vm"]
    inline = [
      "sudo rm -rf /tmp/bootstrap",
      "sudo cloud-init clean --logs || true",
      "sudo rm -f /etc/machine-id && sudo touch /etc/machine-id",
      "sync",
    ]
  }

  // Record what was built so the image id can be fed to Terraform without
  // reading it back out of the cloud API.
  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
    custom_data = {
      image_version  = var.image_version
      ubuntu_release = var.ubuntu_release
      architecture   = var.architecture
      dotfiles_ref   = var.dotfiles_ref
    }
  }
}
