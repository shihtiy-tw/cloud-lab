# Basic test fixture for aws-lab
# Minimal configuration for testing

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "test"
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}

# Simple resource for testing
resource "aws_ssm_parameter" "test" {
  name  = "/test/${var.environment}/param"
  type  = "String"
  value = "test-value"

  tags = var.tags
}

output "parameter_name" {
  value = aws_ssm_parameter.test.name
}

output "parameter_arn" {
  value = aws_ssm_parameter.test.arn
}
