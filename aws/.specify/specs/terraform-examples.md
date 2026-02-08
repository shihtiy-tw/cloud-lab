---
id: spec-014
title: Terraform Module Examples
type: enhancement
priority: medium
status: planned
assignable: true
estimated_hours: 10
tags: [terraform, examples, modules]
---

# Terraform Module Examples for aws-lab

## Overview
Create comprehensive example configurations for Terraform modules.

## Tasks

### Example Configurations (8 tasks)
- [ ] Create basic ECS examples
- [ ] Write high-availability ECS examples
- [ ] Create multi-region deployment examples
- [ ] Write cost-optimized configurations
- [ ] Create development environment examples
- [ ] Write production environment examples
- [ ] Create disaster recovery examples
- [ ] Write blue-green deployment examples

### Module Documentation (4 tasks)
- [ ] Create README for each module with terraform-docs
- [ ] Write usage examples for each module
- [ ] Create variable documentation
- [ ] Write output documentation

## Directory Structure
```
examples/
├── ecs/
│   ├── basic/
│   ├── fargate/
│   ├── ec2/
│   └── service-discovery/
├── vpc/
│   ├── basic/
│   ├── multi-az/
│   └── transit-gateway/
├── environments/
│   ├── dev/
│   ├── staging/
│   └── prod/
└── patterns/
    ├── blue-green/
    ├── canary/
    └── multi-region/
```

## Example Terraform Module

### Basic ECS Service
```hcl
# examples/ecs/basic/main.tf

module "ecs_service" {
  source = "../../modules/ecs-service"
  
  cluster_name = "my-cluster"
  service_name = "my-app"
  
  container_definitions = [{
    name  = "app"
    image = "nginx:latest"
    cpu   = 256
    memory = 512
    
    port_mappings = [{
      container_port = 80
      protocol       = "tcp"
    }]
  }]
  
  desired_count = 2
  
  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

### tfvars Example
```hcl
# examples/environments/dev/terraform.tfvars

environment = "dev"
region      = "us-west-2"

vpc_cidr = "10.0.0.0/16"

ecs_cluster_name = "dev-cluster"

tags = {
  Environment = "development"
  ManagedBy   = "terraform"
  CostCenter  = "engineering"
}
```

## Acceptance Criteria
- All examples are deployable
- Documentation is auto-generated
- Examples cover common patterns
- Cost estimates included
- Security best practices followed

## Dependencies
- None

## Notes
- Include cost breakdown comments
- Document regional considerations
- Provide cleanup instructions
- Include troubleshooting tips
