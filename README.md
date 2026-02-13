# Cloud Lab - Multi-Cloud Infrastructure

[Multi-Cloud]()

A comprehensive multi-cloud infrastructure lab covering AWS, GCP, Azure, and Oracle Cloud. This repository provides consistent, reusable infrastructure patterns and real-world scenarios across cloud providers.

## 📋 Overview

This lab project demonstrates infrastructure-as-code patterns across multiple cloud providers with:

- **Consistent structure** across all clouds
- **Shared patterns** and modules for common architectures
- **Real-world scenarios** for each service
- **Comprehensive testing** with Terratest
- **12-factor compliant** tooling and automation

## 🌥️ Supported Cloud Providers

| Provider   | Status    | Services                               |
| ---------- | --------- | -------------------------------------- |
| **AWS**    | ✅ Active  | ECS, Lambda, S3, EFS, RDS, VPC         |
| **GCP**    | 🔜 Planned | GKE, Cloud Run, GCS, Cloud SQL         |
| **Azure**  | 🔜 Planned | AKS, Container Instances, Blob Storage |
| **Oracle** | 🔜 Planned | OKE, Object Storage, Autonomous DB     |


## 🚀 Quick Start

### Prerequisites

- Terraform >= 1.0
- Cloud provider CLI tools (aws-cli, gcloud, az, oci-cli)
- Go >= 1.20 (for testing)
- make

### AWS Scenarios

``` bash
# Navigate to an AWS ECS scenario
cd aws/compute/ecs/scenarios/ecs-fargate-service-with-alb

# Initialize and plan
terraform init
terraform plan

# Apply
terraform apply

# Cleanup
terraform destroy
```

### Future - Multi-Cloud

``` bash
# Switch cloud context
./scripts/switch-cloud.sh gcp

# Deploy GKE cluster (example)
cd gcp/compute/gke/scenarios/basic-cluster
terraform init && terraform apply
```

## 📁 Project Structure

```
cloud-lab/
├── aws/                    # AWS infrastructure
│   ├── compute/            # ECS, EC2, Lambda
│   ├── storage/            # S3, EFS
│   ├── database/           # RDS, DynamoDB
│   ├── networking/         # VPC, Route53, CloudFront
│   ├── security/           # IAM, KMS
│   └── monitoring/         # CloudWatch
├── gcp/                    # GCP infrastructure (future)
│   ├── compute/            # GKE, Cloud Run, GCE
│   ├── storage/            # GCS, Filestore
│   └── ...
├── azure/                  # Azure infrastructure (future)
│   ├── compute/            # AKS, Container Instances
│   ├── storage/            # Blob Storage
│   └── ...
├── oracle/                 # Oracle infrastructure (future)
│   ├── compute/            # OKE, OCI Compute
│   ├── database/           # Autonomous DB
│   └── ...
├── shared/                 # Cross-cloud resources
│   ├── modules/            # Reusable Terraform modules
│   ├── patterns/           # Architecture patterns
│   └── utils/              # Helper tools
├── docs/                   # Documentation
│   ├── architecture/       # Architecture diagrams
│   ├── guides/             # How-to guides
│   └── standards/          # Standards and conventions
├── examples/               # Quick start examples
├── scripts/                # Automation scripts
└── tests/                  # Integration tests
```

## 🔧 Usage

### Service Organization

Each cloud provider follows the same structure:

```
<cloud>/
└── <service-category>/
    └── <service>/
        ├── infrastructure/    # Base infrastructure modules
        ├── scenarios/         # Real-world use cases
        ├── tests/            # Service-specific tests
        ├── utils/            # Helper scripts
        └── README.md         # Service documentation
```

### Running Tests

``` bash
# Run all tests
cd tests
go test -v ./...

# Run specific cloud tests
go test -v -run TestAWS

# Run specific service tests
go test -v -run TestECS
```

## 🎯 Features

### Current (AWS)

- ✅ **ECS**: Fargate and EC2 launch types with ALB integration
- ✅ **Lambda**: Serverless function scenarios (placeholder)
- ✅ **S3**: Object storage patterns
- ✅ **EFS**: Shared file system integration
- ✅ **RDS**: Database scenarios
- ✅ **VPC**: Network infrastructure modules
- ✅ **Monitoring**: CloudWatch dashboards and alarms

### Planned (GCP)

- ⬜ **GKE**: Kubernetes clusters with autopilot
- ⬜ **Cloud Run**: Serverless containers
- ⬜ **GCS**: Object storage
- ⬜ **Cloud SQL**: Managed databases

### Planned (Azure)

- ⬜ **AKS**: Azure Kubernetes Service
- ⬜ **Container Instances**: Serverless containers
- ⬜ **Blob Storage**: Object storage
- ⬜ **SQL Database**: Managed databases

### Planned (Oracle)

- ⬜ **OKE**: Oracle Kubernetes Engine
- ⬜ **Autonomous Database**: Self-driving database
- ⬜ **Object Storage**: OCI object storage

## 📚 Documentation

- [Architecture Overview](docs/architecture/OVERVIEW.md)
- [Quick Start Guide](docs/guides/QUICKSTART.md)
- [Module Development](docs/guides/MODULE_DEVELOPMENT.md)
- [Terraform Style Guide](docs/standards/TERRAFORM_STYLE.md)
- [Tagging Standards](docs/standards/TAGGING_STANDARDS.md)

## 🧪 Testing

This project uses Terratest for infrastructure testing:

``` bash
# Install dependencies
cd tests
go mod download

# Run unit tests
go test -v ./...

# Run integration tests (requires cloud credentials)
go test -v -tags=integration ./...
```

## 🤝 Contributing

Contributions are welcome! When adding new cloud providers or services:

1.  Follow the established directory structure
2.  Include comprehensive documentation
3.  Add integration tests
4.  Update this README
5.  Ensure 12-factor compliance

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- **AWS**: For ECS and comprehensive cloud services
- **GCP**: For Kubernetes and serverless innovations
- **Azure**: For enterprise cloud solutions
- **Oracle**: For autonomous database technology
- **Terraform**: For infrastructure as code

## 🗺️ Roadmap

### Phase 1: AWS (Current)

- [x] ECS infrastructure and scenarios
- [x] Shared modules (VPC, ALB, IAM)
- [x] Storage scenarios (S3, EFS)
- [x] Database scenarios (RDS)
- [x] Testing framework
- [ ] Lambda scenarios
- [ ] Complete EC2 scenarios

### Phase 2: GCP (Next)

- [ ] GKE basic cluster
- [ ] Cloud Run deployments
- [ ] GCS storage patterns
- [ ] Cloud SQL databases
- [ ] VPC networking
- [ ] Shared GCP modules

### Phase 3: Azure

- [ ] AKS cluster setup
- [ ] Container Instances
- [ ] Blob Storage
- [ ] SQL Database
- [ ] VNet configuration

### Phase 4: Oracle

- [ ] OKE cluster
- [ ] Autonomous Database
- [ ] Object Storage
- [ ] VCN setup

### Phase 5: Multi-Cloud

- [ ] Cross-cloud patterns
- [ ] Unified CLI tool
- [ ] Cost comparison tools
- [ ] Multi-cloud deployment orchestration

## 📝 Migration Notes

### From aws-lab (2026-02-01)

This repository was created by migrating the existing `aws-lab` into a multi-cloud structure. All AWS content has been moved to the `aws/` subdirectory, maintaining the same organization while preparing for expansion to other cloud providers.

**What changed**:

- Location: `aws-lab/` → `cloud-lab/aws/`
- Repository name: `aws-lab` → `cloud-lab`
- Structure: Now organized for multi-cloud expansion

**What stayed the same**:

- All AWS infrastructure code
- Module organization
- Testing framework
- Documentation structure
