# cloud-lab Agent Context

**Domain**: Multi-cloud infrastructure and patterns**Location**: `/home/yst/Labs/cloud-lab`**Type**: Monorepo (AWS, GCP, Azure, Oracle)

------------------------------------------------------------------------

## Current Focus

> 🎯 **AWS Services → Migrated from aws-lab** 🔜 **GCP, Azure, Oracle → Future expansion**

------------------------------------------------------------------------

## YOU ARE HERE

```text
cloud-lab/
├── aws/ ← 🔵 ACTIVE (migrated from aws-lab)
│   ├── compute/     # ECS, EC2, Lambda
│   ├── storage/     # S3, EFS
│   ├── database/    # RDS, DynamoDB
│   ├── networking/  # VPC, Route53, CloudFront
│   ├── security/    # IAM, KMS, Secrets Manager
│   └── monitoring/  # CloudWatch, X-Ray
├── gcp/ ← 🟡 PLACEHOLDER (future)
│   ├── compute/     # GCE, GKE, Cloud Run
│   ├── storage/     # GCS, Filestore
│   ├── database/    # Cloud SQL, Firestore
│   ├── networking/  # VPC, Cloud DNS, Cloud CDN
│   ├── security/    # IAM, KMS, Secret Manager
│   └── monitoring/  # Cloud Monitoring, Cloud Trace
├── azure/ ← 🟡 PLACEHOLDER (future)
│   ├── compute/     # VMs, AKS, Container Instances
│   ├── storage/     # Blob Storage, Files
│   ├── database/    # SQL Database, Cosmos DB
│   ├── networking/  # VNet, DNS, CDN
│   ├── security/    # AAD, Key Vault
│   └── monitoring/  # Monitor, Application Insights
├── oracle/ ← 🟡 PLACEHOLDER (future)
│   ├── compute/     # OCI Compute, OKE
│   ├── storage/     # Object Storage, File Storage
│   ├── database/    # Autonomous DB, MySQL
│   ├── networking/  # VCN, DNS, CDN
│   ├── security/    # IAM, Vault
│   └── monitoring/  # Monitoring, Logging
└── shared/
    ├── modules/     # Cross-cloud reusable modules
    ├── patterns/    # Architecture patterns
    └── utils/       # Helper tools
```

------------------------------------------------------------------------

## Structure

### Cloud Provider Organization

Each cloud provider (`aws/`, `gcp/`, `azure/`, `oracle/`) follows a consistent structure:

| Directory     | Purpose                                     |
| ------------- | ------------------------------------------- |
| `compute/`    | VM instances, containers, serverless        |
| `storage/`    | Object storage, file systems, block storage |
| `database/`   | Managed databases, NoSQL services           |
| `networking/` | VPC/VNet, DNS, load balancers, CDN          |
| `security/`   | IAM, encryption, secrets management         |
| `monitoring/` | Metrics, logging, tracing, alerting         |

### Service Organization

Each service has:

- `infrastructure/` - IaC configs (Terraform, CloudFormation, etc.)
- `scenarios/` - Real-world usage patterns and examples
- `tests/` - Integration and unit tests
- `utils/` - Helper scripts and tools
- `README.md` - Service-specific documentation

### Shared Resources

| Directory          | Purpose                            |
| ------------------ | ---------------------------------- |
| `shared/modules/`  | Reusable IaC modules across clouds |
| `shared/patterns/` | Multi-cloud architecture patterns  |
| `shared/utils/`    | Cross-cloud helper tools           |
| `docs/`            | Documentation and guides           |
| `examples/`        | Quick start examples               |
| `scripts/`         | Automation scripts                 |
| `tests/`           | Integration tests                  |

------------------------------------------------------------------------

## Quick Start

### AWS (Current)

``` bash
# ECS Fargate scenario
cd aws/compute/ecs/scenarios/ecs-fargate-service-with-alb
terraform init && terraform plan

# Shared VPC module
cd aws/shared/modules/vpc
terraform init && terraform plan

# Run tests
cd tests
go test -v ./...
```

### GCP (Future)

``` bash
# GKE scenario (example)
cd gcp/compute/gke/scenarios/basic-cluster
terraform init && terraform plan
```

### Azure (Future)

``` bash
# AKS scenario (example)
cd azure/compute/aks/scenarios/basic-cluster
terraform init && terraform plan
```

### Oracle (Future)

``` bash
# OKE scenario (example)
cd oracle/compute/oke/scenarios/basic-cluster
terraform init && terraform plan
```

------------------------------------------------------------------------

## Lab Sessions

| Date       | Focus            | Notes                    |
| ---------- | ---------------- | ------------------------ |
| 2026-02-01 | Initial setup    | Migrated from aws-lab    |
| Future     | GCP expansion    | GKE, Cloud Run scenarios |
| Future     | Azure expansion  | AKS, Container Instances |
| Future     | Oracle expansion | OKE, Autonomous DB       |

------------------------------------------------------------------------

## Context Sources

- `.specify/` - Speckit specs and plans
- `shared/` - Cross-cloud reusable resources
- Each cloud's README.md - Cloud-specific context
- Each service's README.md - Service-specific context

------------------------------------------------------------------------

## 12-Factor Compliance

- **Infrastructure as Code**: Terraform-first approach
- **CLI**: All scripts have --help, --version flags
- **Testing**: Comprehensive test coverage (Terratest, Go)
- **Documentation**: README.md at every level
- **Configuration**: Environment-specific variables
- **Cloud-agnostic patterns**: Where possible

------------------------------------------------------------------------

## Technology Stack

### Infrastructure as Code

- **Terraform**: Primary IaC tool across all clouds
- **CloudFormation**: AWS native (where needed)
- **ARM Templates**: Azure native (where needed)
- **Deployment Manager**: GCP native (where needed)

### Testing

- **Terratest**: Go-based infrastructure testing
- **Go**: Test framework and utilities
- **Shell**: Integration test scripts

### Automation

- **Make**: Task automation
- **Shell scripts**: Helper utilities
- **CI/CD**: GitHub Actions (future)

------------------------------------------------------------------------

## Cloud Provider Status

### ✅ AWS (Active)

- **Compute**: ECS (Fargate, EC2), Lambda placeholders
- **Storage**: S3, EFS scenarios
- **Database**: RDS scenarios
- **Networking**: VPC, ALB
- **Monitoring**: CloudWatch
- **Testing**: Full Terratest suite

### 🔜 GCP (Planned)

- **Compute**: GKE, Cloud Run, GCE
- **Storage**: GCS, Filestore
- **Database**: Cloud SQL, Firestore, Spanner
- **Networking**: VPC, Cloud Load Balancing
- **Monitoring**: Cloud Monitoring, Logging

### 🔜 Azure (Planned)

- **Compute**: AKS, Container Instances, VMs
- **Storage**: Blob Storage, Files, Disks
- **Database**: SQL Database, Cosmos DB
- **Networking**: VNet, Application Gateway
- **Monitoring**: Azure Monitor, Application Insights

### 🔜 Oracle (Planned)

- **Compute**: OKE, OCI Compute
- **Storage**: Object Storage, Block Volumes
- **Database**: Autonomous Database, MySQL
- **Networking**: VCN, Load Balancer
- **Monitoring**: OCI Monitoring, Logging

------------------------------------------------------------------------

## Commands

### AWS

``` bash
# See AWS-specific Makefile
cd aws && make help
```

### Speckit (Spec-Driven Workflow)

- `speckit.specify` - Create new specifications
- `speckit.plan` - Create implementation plans
- `speckit.tasks` - Generate task lists
- `speckit.taskstovibe` - Sync tasks to Vibe Kanban
- `speckit.implement` - Execute implementation

### Cloud Operations (CSP-Aware)

``` bash
# Switch cloud context
make aws                    # or: make gcp, make azure, make oracle
make status                 # show the active context

# Provision infrastructure
make plan CLOUD=aws SERVICE=compute/ecs ENV=dev
make provision CLOUD=aws SERVICE=compute/ecs ENV=dev
make destroy CLOUD=aws SERVICE=compute/ecs ENV=dev

# Run tests
make test CLOUD=aws SERVICE=compute/ecs

# Security scan
make security CLOUD=aws SERVICE=compute/ecs

# Cost analysis
make cost CLOUD=aws

# Initialize new service
make init CLOUD=aws CATEGORY=compute NAME=my-service
```

Every target above is a thin wrapper over `scripts/cloud.*.sh`; each script
takes `--help`. See `scripts/README.md` for the CLI contract and
`.opencode/command/*.md` for full command documentation.

------------------------------------------------------------------------

## Safety Rules

- Always specify cloud provider and environment explicitly
- Backup before destructive operations
- Test in dev/sandbox accounts first
- Require confirmation for:
    - Resource deletion
    - Production deployments
    - Cross-cloud operations
    - Cost-intensive resources
- Monitor cloud costs actively
- Use cloud-specific best practices for security

------------------------------------------------------------------------

## Migration Notes

### From aws-lab

**Date**: 2026-02-01

**What was migrated**:

- All compute/ecs infrastructure and scenarios
- Shared modules (VPC, ALB, ECS task, IAM roles, ECR)
- Storage scenarios (S3, EFS)
- Database RDS scenarios
- Monitoring CloudWatch configurations
- Documentation and examples
- Test suite

**What changed**:

- Location: `/home/yst/Labs/aws-lab` → `/home/yst/Labs/cloud-lab/aws`
- Structure: Now part of multi-cloud monorepo
- Future: Will add GCP, Azure, Oracle alongside AWS

------------------------------------------------------------------------

## Related Resources

- Project: [[cloud-lab](file:///home/yst/Labs/cloud-lab)]
- AWS Docs: [[aws/README.md](file:///home/yst/Labs/cloud-lab/aws/README.md)]
- Shared Modules: [[shared/modules](file:///home/yst/Labs/cloud-lab/shared/modules)]
- Architecture Patterns: [[shared/patterns](file:///home/yst/Labs/cloud-lab/shared/patterns)]

------------------------------------------------------------------------

## Next Steps

1. ✅ Migrate aws-lab content
2. ⬜ Create GCP foundational infrastructure
3. ⬜ Create Azure foundational infrastructure
4. ⬜ Create Oracle foundational infrastructure
5. ⬜ Develop cross-cloud patterns
6. ⬜ Implement multi-cloud cost tracking
7. ⬜ Create unified CLI tool
