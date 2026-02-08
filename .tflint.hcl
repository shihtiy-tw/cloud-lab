# TFLint Configuration for aws-lab
# https://github.com/terraform-linters/tflint

config {
  module = true
  force = false
}

# AWS Provider Plugin
plugin "aws" {
  enabled = true
  version = "0.29.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Terraform Rules
rule "terraform_naming_convention" {
  enabled = true
  
  # Resource naming: snake_case
  resource {
    format = "snake_case"
  }
  
  # Variable naming: snake_case
  variable {
    format = "snake_case"
  }
  
  # Output naming: snake_case
  output {
    format = "snake_case"
  }
  
  # Local naming: snake_case
  local {
    format = "snake_case"
  }
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = true
}

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_empty_list_equality" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
  
  style = "semver"
  default_branches = ["main", "master"]
}

rule "terraform_module_version" {
  enabled = true
}

rule "terraform_standard_module_structure" {
  enabled = true
}

rule "terraform_workspace_remote" {
  enabled = true
}

# AWS Specific Rules
rule "aws_instance_invalid_type" {
  enabled = true
}

rule "aws_iam_policy_document_gov_friendly_arns" {
  enabled = false
}

# ECS Specific
rule "aws_ecs_cluster_missing_tags" {
  enabled = true
}

rule "aws_ecs_service_invalid_launch_type" {
  enabled = true
}
