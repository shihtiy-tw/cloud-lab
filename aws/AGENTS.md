# AWS Infrastructure - cloud-lab

**Domain**: AWS services infrastructure and patterns  
**Location**: `/home/yst/Labs/cloud-lab/aws`  
**Type**: Cloud provider module within multi-cloud monorepo  
**Parent**: [cloud-lab](../AGENTS.md)

---

## Current Focus

> 🎯 **Compute → ECS migration from ecs-lab**

---

## YOU ARE HERE

```
cloud-lab/aws/ ← AWS infrastructure within multi-cloud lab
├── compute/
│   ├── ecs/ ← 🔵 ACTIVE (migrated from ecs-lab)
│   ├── ec2/ (placeholder)
│   └── lambda/ (placeholder)
├── storage/
│   ├── s3/
│   └── efs/
├── database/
│   └── rds/
├── networking/
├── security/
└── monitoring/
```

---

## Structure

| Directory | Purpose |
|-----------|---------|
| `shared/` | Terraform modules, architecture patterns |
| `compute/` | ECS, EC2, Lambda |
| `storage/` | S3, EFS |
| `database/` | RDS, DynamoDB |

Each service has:
- `infrastructure/` - Terraform configs
- `scenarios/` - Usage patterns
- `tests/` - Terratest integration tests
- `utils/` - Helper tools

---

## Quick Start

```bash
# ECS scenario
cd compute/ecs/scenarios/fargate-service-with-alb
terraform init && terraform plan

# Shared module
cd shared/modules/vpc
```

---

## Lab Sessions

| Date | Focus | Notes |
|------|-------|-------|
| 2026-01-30 | Initial setup | Migrating from ecs-lab |

---

## Context Sources

- `.specify/` - Speckit specs and plans
- `shared/` - Reusable modules
- Each `*/README.md` - Service-specific context

---

## 12-Factor Compliance

- **Infrastructure**: Terraform-first
- **CLI**: All scripts have --help, --version
- **Testing**: Terratest integration tests

---

## Commands

See: `.opencode/commands/*.md` for lab management
