output "name" {
  description = "Generated base name for resources in this stack."
  value       = local.name
}

output "common_tags" {
  description = "Tag set applied to resources in this stack."
  value       = local.common_tags
}

output "instance_id" {
  description = "EC2 instance id of the dev VM."
  value       = aws_instance.dev_vm.id
}

output "instance_private_ip" {
  description = "Private address of the VM. Reachable from inside the VPC only, which is the entire point."
  value       = aws_instance.dev_vm.private_ip
}

output "availability_zone" {
  description = "AZ the VM and its home volume are pinned to."
  value       = aws_instance.dev_vm.availability_zone
}

output "ami_id" {
  description = "AMI the VM was launched from. Feed this back as var.ami_id to pin the image and stop future plans proposing a replacement."
  value       = aws_instance.dev_vm.ami
}

# The only supported way in. There is no ssh command to output because there is no
# SSH: --document-name is what attaches the logged session preferences, so copy
# this line rather than typing a shorter one from memory.
output "ssm_start_session_command" {
  description = "Command that opens a logged shell on the VM."
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.dev_vm.id} --document-name ${aws_ssm_document.session_prefs.name}"
}

output "ssm_port_forward_command_example" {
  description = "Example of reaching a service on the VM (here, port 3000) without any inbound rule."
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.dev_vm.id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"3000\"],\"localPortNumber\":[\"3000\"]}'"
}

output "data_volume_id" {
  description = "Persistent home volume. Survives `terraform destroy` by design; deleting it is a deliberate, manual act."
  value       = aws_ebs_volume.home.id
}

output "data_volume_device" {
  description = "Where the home volume is attached, and the path the guest sees it at."
  value       = "${aws_volume_attachment.home.device_name} (guest: ${var.data_disk_device})"
}

# Assert-style outputs: they exist so `terraform output` answers the security
# questions directly, without anyone having to read the plan to be sure.
output "public_ip_assertion" {
  description = "Confirms the VM has no public address."
  value       = aws_instance.dev_vm.public_ip == "" ? "OK: no public IP assigned" : "FAIL: public IP ${aws_instance.dev_vm.public_ip} is attached"
}

output "ingress_rule_assertion" {
  description = "Confirms the security group opens nothing inbound."
  value       = length(aws_security_group.dev_vm.ingress) == 0 ? "OK: 0 ingress rules" : "FAIL: ${length(aws_security_group.dev_vm.ingress)} ingress rules present"
}

output "imdsv2_assertion" {
  description = "Confirms instance metadata requires a session token."
  value       = aws_instance.dev_vm.metadata_options[0].http_tokens == "required" ? "OK: IMDSv2 required" : "FAIL: IMDSv1 reachable"
}

output "security_group_id" {
  description = "Egress-only security group attached to the VM."
  value       = aws_security_group.dev_vm.id
}

output "instance_role_arn" {
  description = "Instance role. Scoped to SSM, its own logs and read-only describe; admin is assumed from inside the shell instead."
  value       = aws_iam_role.dev_vm.arn
}

output "session_log_group_name" {
  description = "CloudWatch log group holding session transcripts."
  value       = aws_cloudwatch_log_group.sessions.name
}

output "session_log_bucket" {
  description = "S3 archive for transcripts; empty when enable_session_log_bucket is false."
  value       = var.enable_session_log_bucket ? aws_s3_bucket.sessions[0].id : ""
}

output "ssm_session_document_name" {
  description = "Session document that turns on logging. Pass it with --document-name or the session is not recorded."
  value       = aws_ssm_document.session_prefs.name
}

output "auto_stop_schedule" {
  description = "Scheduled hard stop, and whether it is armed."
  value       = "${var.auto_stop_cron} ${var.auto_stop_timezone} (${aws_scheduler_schedule.auto_stop.state})"
}

output "vpc_id" {
  description = "VPC created for the VM."
  value       = module.vpc.vpc_id
}

output "nat_public_ips" {
  description = "Addresses the VM egresses from, for anything upstream that keeps an allowlist."
  value       = module.vpc.nat_public_ips
}
