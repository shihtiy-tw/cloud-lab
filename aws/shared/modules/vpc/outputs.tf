# vpc_id, vpc_cidr, private_subnet_ids and public_subnet_ids are the contract
# aws/tests/vpc_test.go asserts on. Renaming any of them breaks that test.

output "vpc_id" {
  description = "The ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, ordered to match availability_zones."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, ordered to match availability_zones."
  value       = aws_subnet.public[*].id
}

output "availability_zones" {
  description = <<-EOT
    AZs the subnets were placed in, index-aligned with the subnet outputs.
    Callers that attach a zonal resource -- an EBS volume, for instance -- need
    this to place it in the same AZ as the subnet they chose.
  EOT
  value       = local.az_names
}

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways; empty when enable_nat_gateway is false."
  value       = aws_nat_gateway.main[*].id
}

output "nat_public_ips" {
  description = "Elastic IPs of the NAT gateways. This is the source address private workloads egress from, which is what an upstream allowlist needs."
  value       = aws_eip.nat[*].public_ip
}

output "private_route_table_ids" {
  description = "IDs of the private route tables, one per AZ."
  value       = aws_route_table.private[*].id
}

output "public_route_table_id" {
  description = "ID of the shared public route table."
  value       = aws_route_table.public.id
}
