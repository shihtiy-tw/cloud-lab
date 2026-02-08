# CloudWatch Dashboard for ECS Service
# Creates a comprehensive dashboard for ECS monitoring

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "ecs_service" {
  dashboard_name = "${local.name_prefix}-ecs-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Title
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ECS Service Dashboard - ${var.ecs_service_name}"
        }
      },
      
      # CPU Utilization
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "CPU Utilization"
          region = var.aws_region
          metrics = [
            [
              "AWS/ECS", "CPUUtilization",
              "ClusterName", var.ecs_cluster_name,
              "ServiceName", var.ecs_service_name
            ]
          ]
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      
      # Memory Utilization
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Memory Utilization"
          region = var.aws_region
          metrics = [
            [
              "AWS/ECS", "MemoryUtilization",
              "ClusterName", var.ecs_cluster_name,
              "ServiceName", var.ecs_service_name
            ]
          ]
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      
      # Running Task Count
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Running Tasks"
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights", "RunningTaskCount",
              "ClusterName", var.ecs_cluster_name,
              "ServiceName", var.ecs_service_name
            ]
          ]
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
        }
      },
      
      # Network In/Out
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Network Traffic"
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights", "NetworkRxBytes",
              "ClusterName", var.ecs_cluster_name,
              "ServiceName", var.ecs_service_name,
              { label = "Received" }
            ],
            [
              "ECS/ContainerInsights", "NetworkTxBytes",
              "ClusterName", var.ecs_cluster_name,
              "ServiceName", var.ecs_service_name,
              { label = "Transmitted" }
            ]
          ]
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Sum"
        }
      },
      
      # Current Status
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Task Status"
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights", "DesiredTaskCount",
              "ClusterName", var.ecs_cluster_name,
              "ServiceName", var.ecs_service_name,
              { label = "Desired" }
            ],
            [
              "ECS/ContainerInsights", "RunningTaskCount",
              "ClusterName", var.ecs_cluster_name,
              "ServiceName", var.ecs_service_name,
              { label = "Running" }
            ],
            [
              "ECS/ContainerInsights", "PendingTaskCount",
              "ClusterName", var.ecs_cluster_name,
              "ServiceName", var.ecs_service_name,
              { label = "Pending" }
            ]
          ]
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
        }
      }
    ]
  })
}

# =============================================================================
# Outputs
# =============================================================================

output "dashboard_arn" {
  description = "CloudWatch dashboard ARN"
  value       = aws_cloudwatch_dashboard.ecs_service.dashboard_arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.ecs_service.dashboard_name
}
