output "name" {
  description = "Generated base name for resources in this stack."
  value       = local.name
}

output "common_tags" {
  description = "Tag set applied to resources in this stack."
  value       = local.common_tags
}

output "common_labels" {
  description = "Sanitised, GCP-legal form of common_tags actually applied as labels."
  value       = local.common_labels
}

# ---------------------------------------------------------------------------
# Instance
# ---------------------------------------------------------------------------

output "instance_id" {
  description = "Numeric instance id."
  value       = google_compute_instance.dev_vm.instance_id
}

output "instance_name" {
  description = "Instance name; the argument to `gcloud compute ssh`."
  value       = google_compute_instance.dev_vm.name
}

output "instance_self_link" {
  description = "Self link of the instance."
  value       = google_compute_instance.dev_vm.self_link
}

output "instance_zone" {
  description = "Zone the instance and its persistent home disk live in."
  value       = google_compute_instance.dev_vm.zone
}

output "machine_type" {
  description = "Machine type in use."
  value       = google_compute_instance.dev_vm.machine_type
}

output "boot_image" {
  description = "Image the boot disk was created from, resolved to a concrete self link."
  value       = local.boot_image
}

output "service_account_email" {
  description = "The VM's own identity. Holds logging and monitoring write only; the human's roles are separate."
  value       = google_service_account.dev_vm.email
}

# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------

output "ssh_command" {
  description = "The only supported way in. There is no public SSH endpoint to connect to instead."
  value       = "gcloud compute ssh ${google_compute_instance.dev_vm.name} --tunnel-through-iap --zone ${google_compute_instance.dev_vm.zone} --project ${var.project_id}"
}

output "start_command" {
  description = "Start the box after an idle or scheduled stop."
  value       = "gcloud compute instances start ${google_compute_instance.dev_vm.name} --zone ${google_compute_instance.dev_vm.zone} --project ${var.project_id}"
}

output "stop_command" {
  description = "Stop the box by hand rather than waiting for the idle timer."
  value       = "gcloud compute instances stop ${google_compute_instance.dev_vm.name} --zone ${google_compute_instance.dev_vm.zone} --project ${var.project_id}"
}

# ---------------------------------------------------------------------------
# Security properties, exposed so they can be asserted rather than trusted
# ---------------------------------------------------------------------------

output "external_ip_addresses" {
  description = <<-EOT
    Every external address on the instance. This must be an empty list: the
    instance declares no access_config block, which is what would assign one. An
    output rather than a comment so a test can fail if that ever changes.
  EOT
  value = flatten([
    for nic in google_compute_instance.dev_vm.network_interface : [
      for cfg in nic.access_config : cfg.nat_ip
    ]
  ])
}

output "has_external_ip" {
  description = "False is the requirement. True means someone added an access_config block."
  value = length(flatten([
    for nic in google_compute_instance.dev_vm.network_interface : nic.access_config
  ])) > 0
}

output "internal_ip" {
  description = "The instance's only address. Routable inside the VPC and from the IAP forwarder, and nowhere else."
  value       = google_compute_instance.dev_vm.network_interface[0].network_ip
}

output "oslogin_enabled" {
  description = "Whether SSH keys are managed by IAM rather than by metadata."
  value       = google_compute_instance.dev_vm.metadata["enable-oslogin"] == "TRUE"
}

output "serial_console_enabled" {
  description = "Break-glass serial console state. Expected false outside an active recovery."
  value       = google_compute_instance.dev_vm.metadata["serial-port-enable"] == "TRUE"
}

output "shielded_vm" {
  description = "Secure Boot, vTPM and integrity monitoring state."
  value = {
    secure_boot          = google_compute_instance.dev_vm.shielded_instance_config[0].enable_secure_boot
    vtpm                 = google_compute_instance.dev_vm.shielded_instance_config[0].enable_vtpm
    integrity_monitoring = google_compute_instance.dev_vm.shielded_instance_config[0].enable_integrity_monitoring
  }
}

output "network_tags" {
  description = "Network tags on the instance. Must include the tag the IAP firewall rule targets or the box is unreachable."
  value       = tolist(google_compute_instance.dev_vm.tags)
}

# ---------------------------------------------------------------------------
# Persistent home disk
# ---------------------------------------------------------------------------

output "data_disk_id" {
  description = "Fully qualified id of the persistent home disk."
  value       = google_compute_disk.home.id
}

output "data_disk_name" {
  description = "Name of the persistent home disk."
  value       = google_compute_disk.home.name
}

output "data_disk_self_link" {
  description = "Self link of the persistent home disk."
  value       = google_compute_disk.home.self_link
}

output "data_disk_size" {
  description = "Size of the persistent home disk in GB."
  value       = google_compute_disk.home.size
}

output "data_disk_device_path" {
  description = "Guest path the disk appears at, and the DATA_DISK_DEVICE value handed to seed-home.sh. Bound to the attached disk's device_name."
  value       = local.data_disk_device_path
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

output "network_name" {
  description = "VPC network the instance sits in."
  value       = module.network.network_name
}

output "subnetwork_name" {
  description = "Private subnetwork the instance sits in."
  value       = module.network.subnetwork_name
}

output "subnet_cidr" {
  description = "Range of the private subnetwork."
  value       = module.network.subnet_cidr
}

output "iap_firewall_name" {
  description = "Name of the one rule that allows tcp:22."
  value       = module.network.iap_firewall_name
}

output "iap_firewall_source_ranges" {
  description = "Source ranges on that rule. Must be exactly [\"35.235.240.0/20\"]."
  value       = module.network.iap_firewall_source_ranges
}

output "nat_enabled" {
  description = "Whether Cloud NAT egress exists. It is the dominant standing cost of this stack."
  value       = module.network.nat_enabled
}

# ---------------------------------------------------------------------------
# Access
# ---------------------------------------------------------------------------

output "developer_principals" {
  description = "Principals granted IAP tunnel and OS Login access. An empty list means nobody can log in."
  value       = var.developer_principals
}

output "auto_stop_schedule" {
  description = "Scheduled stop backstop, or null when disabled."
  value = var.auto_stop_enabled ? {
    stop      = var.vm_stop_schedule
    start     = var.vm_start_schedule != "" ? var.vm_start_schedule : "none (start on demand)"
    time_zone = var.schedule_time_zone
  } : null
}

output "idle_shutdown" {
  description = "On-box idle shutdown configuration written to /etc/dev-vm/idle-shutdown.env."
  value = {
    enabled                = var.idle_shutdown_enabled
    idle_minutes           = var.idle_minutes
    check_interval_minutes = local.idle_check_interval_minutes
    load_threshold         = var.idle_load_threshold
    ignore_containers      = var.idle_ignore_containers
  }
}
