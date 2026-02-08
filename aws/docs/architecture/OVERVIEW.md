# AWS-Lab Architecture Overview

This document describes the high-level architecture of aws-lab.

## System Context

```mermaid
graph TB
    subgraph "aws-lab"
        A[Terraform Modules] --> B[Compute]
        A --> C[Database]
        A --> D[Storage]
        A --> E[Networking]
    end
    
    F[DevOps Engineer] --> A
    A --> G[AWS Cloud]
    
    subgraph "AWS Services"
        G --> H[ECS]
        G --> I[RDS]
        G --> J[S3]
        G --> K[VPC]
    end
```

## Module Architecture

### Core Modules

| Module | Purpose | Location |
|--------|---------|----------|
| **VPC** | Network infrastructure | `shared/vpc/` |
| **ECS** | Container orchestration | `compute/ecs/` |
| **RDS** | Managed databases | `database/rds/` |
| **S3** | Object storage | `storage/s3/` |

### Directory Structure

```
aws-lab/
├── compute/
│   └── ecs/              # ECS clusters and services
│       ├── cluster/      # Cluster module
│       └── service/      # Service module
├── database/
│   └── rds/              # RDS instances
├── storage/
│   └── s3/               # S3 buckets
├── shared/
│   ├── vpc/              # VPC and networking
│   └── iam/              # IAM roles and policies
├── environments/
│   ├── dev/              # Development environment
│   ├── staging/          # Staging environment
│   └── prod/             # Production environment
├── tests/                # Terratest tests
└── examples/             # Example configurations
```

## Module Structure

Each module follows a standard structure:

```
modules/<module-name>/
├── main.tf               # Primary resources
├── variables.tf          # Input variables
├── outputs.tf            # Output values
├── versions.tf           # Provider requirements
├── locals.tf             # Local values
├── data.tf               # Data sources (if needed)
├── iam.tf                # IAM resources (if needed)
├── README.md             # Auto-generated docs
└── doc.md                # Module description
```

## Data Flow

### Deployment Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant TF as Terraform
    participant AWS as AWS

    Dev->>GH: Push code
    GH->>GH: Run validation workflow
    GH->>TF: terraform plan
    TF->>AWS: Query state
    AWS-->>TF: Current state
    TF-->>GH: Plan output
    GH-->>Dev: PR comment with plan
    Dev->>GH: Approve PR
    GH->>TF: terraform apply
    TF->>AWS: Create/Update resources
    AWS-->>TF: Success
    TF-->>GH: Apply complete
```

### State Management

```mermaid
graph LR
    A[Local Terraform] --> B[S3 Backend]
    B --> C[terraform.tfstate]
    A --> D[DynamoDB]
    D --> E[State Lock]
```

## Networking Architecture

```mermaid
graph TB
    subgraph VPC
        subgraph "Public Subnets"
            ALB[Application Load Balancer]
            NAT[NAT Gateway]
        end
        
        subgraph "Private Subnets"
            ECS[ECS Tasks]
            RDS[(RDS)]
        end
    end
    
    Internet((Internet)) --> ALB
    ALB --> ECS
    ECS --> RDS
    ECS --> NAT
    NAT --> Internet
```

## ECS Architecture

```mermaid
graph TB
    subgraph "ECS Cluster"
        subgraph "Fargate"
            T1[Task 1]
            T2[Task 2]
            T3[Task 3]
        end
    end
    
    ALB[ALB] --> T1
    ALB --> T2
    ALB --> T3
    
    T1 --> RDS[(RDS)]
    T2 --> RDS
    T3 --> RDS
    
    T1 --> S3[S3]
    T2 --> S3
    T3 --> S3
```

## Security Model

### IAM Role Hierarchy

```
Account
├── Terraform Execution Role
│   ├── Can create/modify resources
│   └── Uses OIDC for GitHub Actions
│
├── ECS Task Execution Role
│   ├── Pull container images
│   ├── Write CloudWatch logs
│   └── Read secrets
│
└── ECS Task Role
    ├── Application-specific permissions
    └── Access to S3, DynamoDB, etc.
```

### Network Security

- VPC with public/private subnet separation
- Security groups with least-privilege rules
- NACLs for additional defense
- VPC endpoints for AWS service access

## Environments

| Environment | Purpose | Resources |
|-------------|---------|-----------|
| `dev` | Development | Minimal, single AZ |
| `staging` | Testing | Production-like, smaller |
| `prod` | Production | HA, multi-AZ |

### Environment Configuration

```hcl
# environments/dev/terraform.tfvars
environment = "dev"
instance_count = 1
multi_az = false

# environments/prod/terraform.tfvars
environment = "prod"
instance_count = 3
multi_az = true
```

## Cost Optimization

- Fargate Spot for non-production
- Right-sized instances
- S3 lifecycle policies
- Reserved capacity for production

## Monitoring & Observability

| Component | Tool |
|-----------|------|
| Metrics | CloudWatch Metrics |
| Logs | CloudWatch Logs |
| Traces | X-Ray |
| Dashboards | CloudWatch Dashboards |
| Alerts | CloudWatch Alarms → SNS |

---

*Last updated: 2026-01-31*
