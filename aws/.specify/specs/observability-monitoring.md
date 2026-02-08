---
id: spec-015
title: Observability & Monitoring
type: enhancement
priority: medium
status: planned
assignable: true
estimated_hours: 8
tags: [observability, cloudwatch, xray]
---

# Observability & Monitoring for aws-lab

## Overview
Define CloudWatch dashboards, alarms, and monitoring configurations.

## Tasks

### CloudWatch Dashboards (3 tasks)
- [ ] Create ECS service dashboard JSON
- [ ] Write VPC flow logs dashboard
- [ ] Create cost monitoring dashboard

### Alarm Definitions (3 tasks)
- [ ] Write CloudWatch alarm templates
- [ ] Create SNS notification configurations
- [ ] Define alarm escalation policies

### Monitoring Configuration (2 tasks)
- [ ] Create X-Ray tracing configuration
- [ ] Write CloudWatch Logs Insights queries

## Dashboard Examples

### ECS Service Dashboard
```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ECS", "CPUUtilization", {"stat": "Average"}],
          [".", "MemoryUtilization", {"stat": "Average"}]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-west-2",
        "title": "ECS Service Metrics"
      }
    }
  ]
}
```

### CloudWatch Alarms (Terraform)
```hcl
# monitoring/alarms/ecs-service.tf

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.service_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "CPU utilization is too high"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.service_name
  }
}
```

### CloudWatch Logs Insights Queries
```sql
-- Query: Top 10 slowest API endpoints
fields @timestamp, request_uri, response_time
| filter response_time > 1000
| sort response_time desc
| limit 10

-- Query: Error rate by service
fields @timestamp, service_name, error_code
| filter level = "ERROR"
| stats count() by service_name, error_code
```

## Acceptance Criteria
- All dashboards are importable
- Alarms are tested
- Queries return expected results
- Documentation is complete

## Dependencies
- None

## Notes
- Use CloudWatch Dashboard templates
- Document alarm thresholds
- Provide runbook links
- Include cost optimization tips
