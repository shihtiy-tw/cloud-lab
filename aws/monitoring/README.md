# Monitoring Configuration

This directory contains monitoring configurations for aws-lab infrastructure.

## Structure

```
monitoring/
├── README.md               # This file
├── cloudwatch/             # CloudWatch configurations
│   ├── alarms.tf           # CloudWatch alarm definitions
│   ├── dashboards.tf       # CloudWatch dashboard definitions
│   └── log-groups.tf       # Log group configurations
├── dashboards/             # Dashboard JSON definitions
│   └── ecs-service.json
└── modules/                # Reusable monitoring modules
```

## CloudWatch Alarms

### ECS Alarms

| Alarm | Condition | Severity |
|-------|-----------|----------|
| ECS CPU High | CPU > 80% for 5m | Warning |
| ECS Memory High | Memory > 85% for 5m | Warning |
| ECS Task Unhealthy | Healthy tasks < 1 | Critical |
| ALB 5xx Errors | 5xx > 10/min | Critical |

### RDS Alarms

| Alarm | Condition | Severity |
|-------|-----------|----------|
| RDS CPU High | CPU > 80% for 10m | Warning |
| RDS Storage Low | Free storage < 10GB | Warning |
| RDS Connections High | Connections > 80% | Warning |

## Usage

### Apply as Terraform Module

```hcl
module "monitoring" {
  source = "./monitoring/cloudwatch"
  
  project_name     = var.project_name
  environment      = var.environment
  ecs_cluster_name = module.ecs.cluster_name
  ecs_service_name = module.service.name
  
  alert_email = "alerts@example.com"
}
```

### Import Dashboards

CloudWatch dashboards are created via Terraform:

```bash
cd monitoring/cloudwatch
terraform init && terraform apply
```

## Dashboard Previews

### ECS Service Dashboard

Shows:
- CPU and Memory utilization
- Task count over time
- Request count and latency
- Error rates

## Alert Routing

```
Critical Alerts → SNS → PagerDuty
Warning Alerts → SNS → Slack
Info Alerts → CloudWatch Logs
```

## Best Practices

1. **Tagging**: All alarms are tagged for cost allocation
2. **Namespacing**: Prefix all metrics with project name
3. **Retention**: Log groups have defined retention policies
4. **Actions**: Every alarm has defined actions

---

*Last updated: 2026-01-31*
