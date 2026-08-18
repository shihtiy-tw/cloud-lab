output "network_id" {
  description = "Fully qualified id of the VPC network."
  value       = google_compute_network.main.id
}

output "network_name" {
  description = "Name of the VPC network."
  value       = google_compute_network.main.name
}

output "network_self_link" {
  description = "Self link of the VPC network."
  value       = google_compute_network.main.self_link
}

output "subnetwork_id" {
  description = "Fully qualified id of the private subnetwork."
  value       = google_compute_subnetwork.main.id
}

output "subnetwork_name" {
  description = "Name of the private subnetwork."
  value       = google_compute_subnetwork.main.name
}

output "subnetwork_self_link" {
  description = "Self link of the private subnetwork. This is what an instance's network_interface should reference."
  value       = google_compute_subnetwork.main.self_link
}

output "subnet_cidr" {
  description = "CIDR range assigned to the subnetwork, carved from vpc_cidr."
  value       = google_compute_subnetwork.main.ip_cidr_range
}

output "iap_ssh_target_tags" {
  description = <<-EOT
    Network tags the IAP SSH rule matches. An instance that does not carry one of
    these is unreachable, so consumers should read this rather than hardcode the
    tag and drift from the rule.
  EOT
  value       = var.iap_target_tags
}

output "iap_firewall_name" {
  description = "Name of the IAP SSH ingress rule."
  value       = google_compute_firewall.iap_ssh.name
}

output "iap_firewall_source_ranges" {
  description = "Source ranges on the SSH ingress rule. Asserted by the integration tests; must only ever be the IAP range."
  value       = tolist(google_compute_firewall.iap_ssh.source_ranges)
}

output "nat_enabled" {
  description = "Whether Cloud NAT egress was created."
  value       = var.enable_cloud_nat
}

output "nat_name" {
  description = "Name of the Cloud NAT gateway, or null when egress is disabled."
  value       = try(google_compute_router_nat.main[0].name, null)
}

output "router_name" {
  description = "Name of the Cloud Router hosting NAT, or null when egress is disabled."
  value       = try(google_compute_router.nat[0].name, null)
}
