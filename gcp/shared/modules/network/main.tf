# A VPC sized for one private VM reached only through IAP TCP forwarding.
#
# The shape is deliberately unlike aws/shared/modules/vpc: there are no public
# and private subnets here because GCP has no per-subnet internet gateway. A
# subnetwork is private exactly when its instances have no external IP, and
# egress comes from Cloud NAT attached to a Cloud Router. So one subnetwork is
# the whole story, and "public" is a property of the instance, not the subnet.

locals {
  name = "${var.project_name}-${var.environment}"

  # See var.vpc_cidr: the network itself carries no range, so the plan is carved
  # here and only the subnetwork holds an address block.
  subnet_cidr = cidrsubnet(var.vpc_cidr, var.subnet_newbits, 0)

  # google_compute_network, _subnetwork, _router and _firewall have no labels
  # field -- in GCP labels are a compute/storage concept, not a networking one.
  # Silently dropping var.labels would lose the ownership trail on exactly the
  # resources someone will later find in the console and ask "whose is this?", so
  # the label set is folded into `description`, the only free-form field these
  # resources expose.
  label_description = join(" ", [for k in sort(keys(var.labels)) : "${k}=${var.labels[k]}"])
}

# ---------------------------------------------------------------------------
# Network and subnetwork
# ---------------------------------------------------------------------------

resource "google_compute_network" "main" {
  project     = var.project_id
  name        = "${local.name}-vpc"
  description = trimspace("VPC for ${local.name}, managed by terraform. ${local.label_description}")

  # An auto-mode VPC creates a subnet in every region and ships permissive
  # default firewall rules (default-allow-ssh opens 22 to 0.0.0.0/0). Both are
  # the exact opposite of an IAP-only posture, and neither is something you can
  # retrofit -- auto_create_subnetworks cannot be flipped without recreating the
  # network.
  auto_create_subnetworks = false

  # REGIONAL keeps route advertisement inside the region. Nothing here spans
  # regions, and global routing is the setting people turn on and forget.
  routing_mode = "REGIONAL"

  # The default 0.0.0.0/0 route to the internet gateway is what Cloud NAT
  # translates onto, so deleting it would break egress even though no instance
  # has an external IP.
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "main" {
  project       = var.project_id
  name          = "${local.name}-subnet"
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = local.subnet_cidr
  description   = trimspace("Private subnetwork for ${local.name}. ${local.label_description}")

  # Lets an instance with no external IP reach Google APIs over Google's own
  # network: logging, monitoring, OS Login key lookups and the IAP control plane
  # all go this way. Without it a private VM cannot even write its own logs, and
  # every API call would be pushed through Cloud NAT instead.
  private_ip_google_access = true

  # Flow logs are the only record of what a box with no public IP talked to, so
  # they are on by default. The sampling and aggregation settings exist because
  # this is billed per GB ingested and a chatty dev box can produce a surprising
  # amount of it.
  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []

    content {
      aggregation_interval = "INTERVAL_10_MIN"
      flow_sampling        = var.flow_log_sampling
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

# ---------------------------------------------------------------------------
# Egress -- Cloud Router plus Cloud NAT
# ---------------------------------------------------------------------------
#
# private_ip_google_access covers *.googleapis.com and nothing else. The dev VM
# has to reach the Ubuntu archive, GitHub and container registries on every
# `make install`, so it needs real outbound internet. Cloud NAT provides it
# without giving any instance an inbound-reachable address, which is the only
# form of egress compatible with the no-public-IP requirement.

resource "google_compute_router" "nat" {
  count = var.enable_cloud_nat ? 1 : 0

  project     = var.project_id
  name        = "${local.name}-router"
  region      = var.region
  network     = google_compute_network.main.id
  description = trimspace("Cloud Router hosting NAT for ${local.name}. ${local.label_description}")
}

resource "google_compute_router_nat" "main" {
  count = var.enable_cloud_nat ? 1 : 0

  project = var.project_id
  name    = "${local.name}-nat"
  region  = var.region
  router  = google_compute_router.nat[0].name

  # AUTO_ONLY lets Google allocate and rotate the egress addresses. Reserving
  # static IPs only matters when a third party allowlists you, and each reserved
  # address is another thing to pay for and clean up.
  nat_ip_allocate_option = "AUTO_ONLY"

  # Enumerate the subnetwork instead of ALL_SUBNETWORKS_ALL_IP_RANGES so that a
  # subnetwork added to this VPC later does not silently inherit egress.
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.main.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  # ERRORS_ONLY, not ALL: successful translations are high-volume and billed,
  # while dropped ones are what you actually need when egress mysteriously
  # stops (usually port exhaustion).
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ---------------------------------------------------------------------------
# Firewall -- the entire ingress story
# ---------------------------------------------------------------------------

resource "google_compute_firewall" "iap_ssh" {
  project     = var.project_id
  name        = "${local.name}-allow-ssh-from-iap"
  network     = google_compute_network.main.name
  description = "Allow SSH from the IAP TCP forwarding range only. The sole ingress path to tagged instances."
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # 35.235.240.0/20 is the only range IAP TCP forwarding originates from, and it
  # is not routable from the internet -- a packet can only arrive from it after
  # IAP has authenticated and authorised the caller against IAM.
  #
  # This is the one ingress rule in the VPC. Never widen it and never add
  # 0.0.0.0/0 "just to debug": that single edit converts an IAP-brokered box into
  # an internet-exposed SSH server, which is precisely what this design exists to
  # prevent. If IAP is broken, use the serial console recovery path documented in
  # gcp/compute/dev-vm/README.md instead.
  source_ranges = ["35.235.240.0/20"]
  target_tags   = var.iap_target_tags

  # Firewall Rules Logging on the allow path is how "who reached this box, when?"
  # gets answered alongside the IAP and OS Login audit entries.
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "deny_all_ingress" {
  project     = var.project_id
  name        = "${local.name}-deny-all-ingress"
  network     = google_compute_network.main.name
  description = "Explicit lowest-precedence ingress deny. Logged, unlike the implied deny it shadows."
  direction   = "INGRESS"

  # A higher priority number is *lower* precedence, so this loses to the IAP rule
  # at 1000 and to anything anyone adds in between. It sits just above GCP's
  # implied deny at 65535.
  priority = 65533

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  # Being honest about what this buys: it changes nothing about reachability,
  # because the implied deny already blocks the same traffic. It buys two things.
  # First, logging -- you cannot enable logging on GCP's implied rules, so
  # without this rule blocked ingress attempts are invisible. Second, review:
  # any future "allow from anywhere" shows up as an explicit override of a rule
  # that exists in code, rather than as a change against an invisible baseline.
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}
