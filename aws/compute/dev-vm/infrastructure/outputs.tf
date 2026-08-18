output "name" {
  description = "Generated base name for resources in this stack."
  value       = local.name
}

output "common_tags" {
  description = "Tag set applied to resources in this stack."
  value       = local.common_tags
}

# TODO: expose resource ids, ARNs/self-links, and endpoints here.
