# gcp compute - dev-vm
#
# A personal development VM built from the Packer image in shared/packer, with
# one connectivity rule: there is no SSH port on the internet. Access is brokered
# by IAP TCP forwarding, which authorises the caller against IAM before a packet
# ever reaches the box, and authenticates the login through OS Login.
#
# The three properties that make that true, in the order they are easiest to
# break:
#
#   1. The instance has no access_config block, so it has no external IP.
#   2. The only rule allowing tcp:22 sources from 35.235.240.0/20 (see
#      gcp/shared/modules/network).
#   3. OS Login is on, so SSH keys come from IAM rather than from metadata.
#
# Every one of those is a one-line edit away from being false. The comments below
# say so at each site.

locals {
  name = "${var.project_name}-dev-vm-${var.environment}"

  # A zonal data disk pins the VM to one zone forever, so resolving this once
  # here beats letting the provider default drift.
  zone = var.zone != "" ? var.zone : "${var.region}-a"

  # Required tags per docs/standards/TAGGING_STANDARDS.md
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Component   = "compute"
      Owner       = var.owner
      CostCenter  = var.cost_center
    },
    var.tags
  )

  # GCP labels are not AWS tags: keys and values are limited to lowercase
  # letters, digits, `-` and `_`, at most 63 characters, and an empty value is
  # legal but useless. So common_tags cannot be used verbatim -- "CostCenter" and
  # "platform.team" are both rejected by the API, and the failure surfaces at
  # apply time, not plan time.
  #
  # The transform is deliberately lossless-looking rather than lossy: CamelCase
  # keys become kebab-case ("CostCenter" -> "cost-center") instead of collapsing
  # to "costcenter", so the label set still reads like the tag set it came from.
  raw_labels = {
    for k, v in local.common_tags :
    lower(replace(replace(replace(k, "/([a-z0-9])([A-Z])/", "$1-$2"), ".", "-"), "/", "-")) =>
    lower(replace(replace(v, ".", "-"), "/", "-"))
    if v != ""
  }

  common_labels = {
    for k, v in local.raw_labels :
    (length(k) > 63 ? substr(k, 0, 63) : k) => (length(v) > 63 ? substr(v, 0, 63) : v)
  }

  # The instance must carry the tag the IAP firewall rule targets or it is simply
  # unreachable. Reading it from the module keeps the two ends from drifting.
  network_tags = distinct(concat(module.network.iap_ssh_target_tags, var.additional_network_tags))

  # Bound to the attached disk's device_name below. The GCE guest environment
  # publishes attached disks at /dev/disk/by-id/google-<device_name>, and
  # seed-home.sh is told this path explicitly rather than left to guess.
  data_disk_device_name = "devhome"
  data_disk_device_path = "/dev/disk/by-id/google-${local.data_disk_device_name}"

  # The family lookup resolves to a concrete image at plan time; feeding the
  # resulting self_link to the instance (rather than "family/dev-vm-ubuntu2404")
  # means a fresh Packer build shows up as an explicit instance replacement in the
  # plan instead of being silently applied on the next unrelated change. Set
  # var.image_id to freeze it entirely.
  boot_image = var.image_id != "" ? var.image_id : data.google_compute_image.dev_vm[0].self_link

  # Must match OnUnitActiveSec in dev-vm-idle-shutdown.timer, which the image
  # pins at 5min. idle-shutdown.sh accumulates idle time in units of this value.
  idle_check_interval_minutes = 5

  # Service account ids are stricter than resource names: 6-30 characters of
  # [a-z]([-a-z0-9]*[a-z0-9]), and the API rejects rather than truncates. So the
  # id is sanitised, clipped, and stripped of a trailing dash the clip may have
  # left behind, instead of being interpolated and hoped over.
  sa_account_id_raw = replace(lower("${var.project_name}-devvm-${var.environment}"), "/[^a-z0-9-]/", "-")
  sa_account_id = replace(
    length(local.sa_account_id_raw) > 30 ? substr(local.sa_account_id_raw, 0, 30) : local.sa_account_id_raw,
    "/-+$/", ""
  )
}

# ---------------------------------------------------------------------------
# Image
# ---------------------------------------------------------------------------

data "google_compute_image" "dev_vm" {
  # Skipped entirely when an explicit image is pinned, so a pinned deployment does
  # not fail because the family was deleted.
  count = var.image_id == "" ? 1 : 0

  project = var.image_project != "" ? var.image_project : var.project_id
  family  = var.image_family
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

module "network" {
  source = "../../../shared/modules/network"

  project_id   = var.project_id
  project_name = var.project_name
  environment  = var.environment
  region       = var.region
  vpc_cidr     = var.vpc_cidr
  labels       = local.common_labels

  enable_cloud_nat = var.enable_cloud_nat
}

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

resource "google_service_account" "dev_vm" {
  project      = var.project_id
  account_id   = local.sa_account_id
  display_name = "Dev VM ${local.name}"
  description  = "Identity of the dev VM itself. Deliberately near-powerless; admin lives on the human's identity."
}

# The VM's own identity gets write access to logging and monitoring and nothing
# else. It is not project owner, not editor, and not an admin of anything.
#
# This is the point worth defending: the human who uses this box authenticates as
# themselves through IAP and OS Login, and their IAM roles are what let them
# administer the project. The instance's service account is a separate principal
# used by the box's agents, so anything that runs on the box -- a compromised
# dependency in a `make install`, a malicious postinstall script -- inherits only
# what is listed here. Adding roles/editor to this account would hand every
# process on the VM the keys to the project, which is exactly the blast radius
# this split exists to avoid.
resource "google_project_iam_member" "dev_vm_sa" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.dev_vm.email}"
}

# ---------------------------------------------------------------------------
# Persistent home disk
# ---------------------------------------------------------------------------

resource "google_compute_disk" "home" {
  project = var.project_id
  name    = "${local.name}-home"
  zone    = local.zone
  type    = var.data_disk_type
  size    = var.data_disk_size
  labels  = local.common_labels

  description = "Persistent /home/${var.target_user} for ${local.name}. Survives instance destroy."

  # The entire point of the lifecycle design. This disk holds every uncommitted
  # branch, every scratch note and every shell history on the box; the instance is
  # disposable and this is not.
  #
  # Consequence to be aware of: a plain `terraform destroy` of this stack will
  # refuse to run while this is set. That is intended -- see the "Tearing it down"
  # section of the README for the targeted-destroy recipe that removes the
  # expensive resources and leaves the disk.
  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# The instance
# ---------------------------------------------------------------------------

resource "google_compute_instance" "dev_vm" {
  project      = var.project_id
  name         = local.name
  zone         = local.zone
  machine_type = var.machine_type
  description  = "Dotfiles development VM. Reachable only through IAP TCP forwarding."

  labels = local.common_labels

  # Network tags, not labels: these are what firewall rules match on. Dropping the
  # IAP tag here does not weaken security, it just makes the box unreachable.
  tags = local.network_tags

  # Machine type, metadata and disk changes all require a stopped instance, and
  # this box is expected to be stopped most of the time anyway. Without this, a
  # routine change fails with "instance must be stopped" at apply time.
  allow_stopping_for_update = true

  # A dev VM is meant to be replaceable; the data that matters lives on the
  # persistent disk, which has its own prevent_destroy.
  deletion_protection = false

  boot_disk {
    auto_delete = true

    initialize_params {
      image  = local.boot_image
      size   = var.boot_disk_size
      type   = var.boot_disk_type
      labels = local.common_labels
    }
  }

  # device_name is load-bearing: the guest environment symlinks this disk to
  # /dev/disk/by-id/google-devhome, which is the exact path handed to
  # seed-home.sh through /etc/dev-vm/seed-home.env. Rename one without the other
  # and first boot fails to find the disk.
  attached_disk {
    source      = google_compute_disk.home.id
    device_name = local.data_disk_device_name
    mode        = "READ_WRITE"
  }

  network_interface {
    subnetwork = module.network.subnetwork_self_link

    # There is deliberately NO access_config block here.
    #
    # An access_config block is what assigns an external IP address, and its
    # absence is the security requirement -- not a detail, not an oversight, and
    # not something to add back "temporarily to test something". With no external
    # IP this instance is unreachable from the internet regardless of what any
    # firewall rule says, and reachable only through the IAP tunnel that
    # authorises callers against IAM first.
    #
    # If you are here because something cannot reach the internet: egress is
    # Cloud NAT's job and it already works. Adding an external IP would not fix an
    # egress problem, it would only create an ingress one.
  }

  service_account {
    email = google_service_account.dev_vm.email

    # cloud-platform, with IAM doing the actual restriction, is Google's
    # recommended pattern and looks alarming until you know why. Scopes are a
    # legacy, per-instance ceiling that predates IAM; they cannot express "write
    # logs but not read buckets", so narrowing them tends to break unrelated
    # things (the guest agent, OS Login, Ops Agent) while providing no real
    # containment. The effective permissions of this instance are exactly the two
    # roles bound to google_service_account.dev_vm above, and that is where to
    # look -- and where to make changes -- when asking what this VM can do.
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    # SSH keys come from IAM rather than from project or instance metadata, so
    # access is granted and revoked by changing a role binding. Without this, an
    # ssh key in project metadata would be a standing back door that no IAM change
    # can close.
    enable-oslogin = "TRUE"

    # Belt and braces: even with OS Login on, this makes it explicit that
    # project-wide keys are not a path onto this box.
    block-project-ssh-keys = "TRUE"

    # Off unless deliberately enabled. The serial console bypasses OS Login and
    # the firewall entirely; it is the documented break-glass path, not a
    # standing one. See the recovery section of the README.
    serial-port-enable = var.enable_serial_console ? "TRUE" : "FALSE"
  }

  # Hands the image's cloud-agnostic boot scripts their cloud-specific
  # configuration -- above all the data disk device path. See the template for the
  # boot-ordering caveat on the very first start.
  metadata_startup_script = templatefile("${path.module}/templates/startup-script.sh.tftpl", {
    target_user            = var.target_user
    home_seed_dir          = var.home_seed_dir
    fs_label               = var.fs_label
    data_disk_device       = local.data_disk_device_path
    idle_enabled           = var.idle_shutdown_enabled ? "true" : "false"
    idle_minutes           = var.idle_minutes
    check_interval_minutes = local.idle_check_interval_minutes
    load_threshold         = var.idle_load_threshold
    ignore_containers      = var.idle_ignore_containers ? "true" : "false"
  })

  # Measured boot. Secure Boot rejects unsigned kernel modules, vTPM provides a
  # measured boot chain, and integrity monitoring reports when those measurements
  # change from the baseline -- which is how you find out a box was tampered with
  # rather than assuming it was not. Free on the Ubuntu images, which are all UEFI
  # and shielded-capable.
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    # A dev box should come back after host maintenance without anyone noticing.
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
    provisioning_model  = "STANDARD"
  }

  # The scheduled-stop backstop, attached by self link. An instance accepts at
  # most one schedule policy, hence the single-element list.
  resource_policies = var.auto_stop_enabled ? [google_compute_resource_policy.auto_stop[0].self_link] : []

  depends_on = [
    # Without egress in place the startup script may run before apt or GitHub are
    # reachable, which does not break this stack but does make first-boot logs
    # confusing to read.
    module.network,
  ]
}

# ---------------------------------------------------------------------------
# Scheduled stop -- the backstop for the on-box idle timer
# ---------------------------------------------------------------------------
#
# The on-box timer in shared/bootstrap/idle-shutdown.sh reacts to actual
# idleness, which is the better signal, but it cannot help if the box wedges or
# if something pins the load average. This is the dumb clock that always works.
#
# Operational prerequisite: instance schedule policies are executed by the
# Compute Engine service agent
# (service-<project-number>@compute-system.iam.gserviceaccount.com), which needs
# roles/compute.instanceAdmin.v1 on the project. Google grants it automatically
# the first time a schedule is created through the console, but a
# Terraform-first project usually has not been through that path -- and the
# failure mode is silent: the policy exists, attaches cleanly, and simply never
# fires. Grant it once per project, out of band, with the command in the README.

resource "google_compute_resource_policy" "auto_stop" {
  count = var.auto_stop_enabled ? 1 : 0

  project     = var.project_id
  name        = "${local.name}-schedule"
  region      = var.region
  description = "Scheduled stop backstop for ${local.name}."

  instance_schedule_policy {
    # A cron expression is meaningless without this; the default of UTC would stop
    # the box in the middle of someone's afternoon.
    time_zone = var.schedule_time_zone

    vm_stop_schedule {
      schedule = var.vm_stop_schedule
    }

    # Optional half. An automatic start bills for every morning the box was not
    # going to be used, so it is opt-in.
    dynamic "vm_start_schedule" {
      for_each = var.vm_start_schedule != "" ? [1] : []

      content {
        schedule = var.vm_start_schedule
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Access -- the bindings that actually grant it
# ---------------------------------------------------------------------------
#
# These two bindings are the entire access story. The box has no external IP and
# no metadata SSH keys, so there is no path onto it that does not go through
# both: IAP has to authorise the tunnel, and OS Login has to authorise the login.
# Remove a principal from here and their access is gone at the next connection --
# no key rotation, no host to clean up.
#
# Both are bound per instance rather than per project. A project-level
# tunnelResourceAccessor grants tunnels to every VM in the project, including
# ones added later; this is the narrow version.

resource "google_iap_tunnel_instance_iam_member" "developers" {
  for_each = toset(var.developer_principals)

  project  = var.project_id
  zone     = local.zone
  instance = google_compute_instance.dev_vm.name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}

resource "google_compute_instance_iam_member" "os_login" {
  for_each = toset(var.developer_principals)

  project       = var.project_id
  zone          = local.zone
  instance_name = google_compute_instance.dev_vm.name

  # osAdminLogin includes sudo. On a personal box that is the whole point; on a
  # shared one, osLogin plus a deliberate escalation is the better shape.
  role   = var.os_login_admin ? "roles/compute.osAdminLogin" : "roles/compute.osLogin"
  member = each.value
}
