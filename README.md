# Cloud Lab - Multi-Cloud Infrastructure

A multi-cloud infrastructure lab covering AWS, GCP, Azure, and Oracle Cloud. This
repository provides consistent, reusable infrastructure patterns and real-world
scenarios across cloud providers.

## 📋 Overview

This lab project demonstrates infrastructure-as-code patterns across multiple
cloud providers with:

- **Consistent structure** across all clouds
- **Shared patterns** and modules for common architectures
- **Real-world scenarios** for each service
- **Comprehensive testing** with Terratest
- **12-factor compliant** tooling and automation

## 🌥️ Supported Cloud Providers

| Provider | Status | What exists today |
| -------- | ------ | ----------------- |
| **AWS** | ✅ Applied | ECS, Lambda, S3, EFS, RDS, VPC, dev-vm (101 `.tf` files) |
| **GCP** | 🟡 Written | Network module + dev-vm; validates, never applied |
| **Azure** | 🟡 Written | Network module + dev-vm; validates, never applied |
| **Oracle** | ⬜ Scaffold | Directory structure only, 0 `.tf` files |

**"Written" is not "working."** GCP and Azure Terraform passes
`terraform validate` and its security properties are verifiable by inspection, but
there are no credentials for either cloud yet, so nothing has been applied. Treat
those stacks as unproven until someone runs `terraform plan` against a real
project or subscription. See `.progress.md` for the honest status of each area.

## 🚀 Quick Start

### Prerequisites

- Terraform >= 1.5
- Packer >= 1.9 (for the dev-vm golden images)
- Cloud provider CLI tools (`aws`, `gcloud`, `az`, `oci`)
- Go >= 1.20 (for testing)
- `make`

Run `./aws/scripts/setup-dev.sh` to install the linting and security toolchain
(`tflint`, `tfsec`, `terraform-docs`, `checkov`). Several pre-commit hooks sit on
the manual stage until these are present — see
[`.pre-commit-config.yaml`](.pre-commit-config.yaml) for why.

### The cloud.* commands

Seven cloud-aware wrappers handle the common lifecycle across every provider:

```bash
./scripts/cloud.init.sh --cloud gcp --category compute --name dev-vm --with-tests
./scripts/cloud.provision.sh --cloud aws --service compute/dev-vm --env dev
./scripts/cloud.test.sh      --cloud aws --service compute/dev-vm
./scripts/cloud.security.sh  --cloud aws --service compute/dev-vm
./scripts/cloud.cost.sh      --cloud aws --service compute/dev-vm
./scripts/cloud.docs.sh      --cloud aws --service compute/dev-vm
./scripts/cloud.switch.sh    --cloud gcp
```

They share an exit-code contract — `0` ok, `1` error, `2` usage, `3` missing
dependency, `4` security finding — documented in
[`scripts/README.md`](scripts/README.md). Equivalent `make` targets exist for
each.

### Development VM (all three clouds)

The flagship multi-cloud service: an Ubuntu dev box preloaded with dotfiles, the
Kubernetes toolchain, and neovim, reachable **without exposing SSH to the
internet**.

```bash
packer build -only='dev-vm.amazon-ebs.dev-vm' shared/packer/
./scripts/cloud.provision.sh --cloud aws --service compute/dev-vm --env dev
aws ssm start-session --target "$INSTANCE_ID"
```

Each cloud brokers access its own way, and none of them opens port 22 to the
world:

| Cloud | Broker | Ingress rules on the VM | Broker cost |
| ----- | ------ | ----------------------- | ----------- |
| AWS | SSM Session Manager | none at all | $0 |
| GCP | IAP TCP forwarding | one, from `35.235.240.0/20` | $0 |
| Azure | Bastion (Developer SKU) | none (out-of-band) | $0 |

Full details in [`.specify/003-dev-vm/`](.specify/003-dev-vm/) and each service's
README. Because there is no SSH fallback, read
[the break-glass runbook](docs/runbooks/dev-vm-break-glass.md) **before** you need
it.

### AWS scenarios

```bash
cd aws/compute/ecs/scenarios/ecs-fargate-service-with-alb
terraform init
terraform plan
terraform apply
terraform destroy
```

## 📁 Project Structure

```text
cloud-lab/
├── aws/                    # AWS infrastructure (applied)
│   ├── compute/            # ECS, EC2, Lambda, dev-vm
│   ├── storage/            # S3, EFS
│   ├── database/           # RDS, DynamoDB
│   ├── networking/         # VPC, Route53, CloudFront
│   ├── security/           # IAM, KMS
│   ├── monitoring/         # CloudWatch
│   ├── shared/modules/     # AWS-only reusable modules (vpc, iam-roles, alb...)
│   └── docs/               # AWS architecture, guides and standards
├── gcp/                    # GCP infrastructure (written, not applied)
│   ├── compute/dev-vm/
│   └── shared/modules/     # network (VPC, Cloud NAT, IAP firewall)
├── azure/                  # Azure infrastructure (written, not applied)
│   ├── compute/dev-vm/
│   └── shared/modules/     # network (VNet, NAT Gateway, NSG)
├── oracle/                 # Oracle infrastructure (scaffolding only)
├── shared/                 # CROSS-CLOUD ONLY -- nothing provider-specific
│   ├── bootstrap/          # dev-vm image provisioner, home seeding, idle shutdown
│   └── packer/             # one dev-vm template, three sources
├── docs/                   # Cross-cloud documentation
│   ├── guides/             # How-to guides
│   └── runbooks/           # Operational recovery procedures
├── .specify/               # Specifications (001-structure, 002-scripts, 003-dev-vm)
├── scripts/                # The seven cloud.* commands + lib/
├── examples/               # Quick start examples (empty)
└── tests/                  # Cross-cloud integration tests (empty)
```

Note the distinction between `shared/` and `<cloud>/shared/`: the root one is for
genuinely cloud-agnostic assets, while `aws/shared/modules/` and friends hold
provider-specific modules. Root `examples/` and `tests/` are still empty.

## 🔧 Usage

### Service Organization

Each cloud provider follows the same structure:

```text
<cloud>/
└── <service-category>/
    └── <service>/
        ├── infrastructure/   # Base infrastructure modules
        ├── scenarios/        # Real-world use cases
        ├── tests/            # Service-specific tests
        ├── utils/            # Helper scripts
        └── README.md         # Service documentation
```

### Running Tests

Tests live next to the service they cover, each as its own Go module. The root
`tests/` directory is a placeholder and contains nothing yet.

```bash
./scripts/cloud.test.sh --cloud aws --service compute/dev-vm

# or directly
cd aws/compute/dev-vm/tests
go mod tidy
go test -short ./...     # unit only; integration tests self-skip without credentials
go test -v ./...         # integration too; needs cloud credentials
```

Integration tests self-skip on `testing.Short()`, so `-short` stays green with no
credentials. (`aws/tests/` uses its `helpers.SkipInShortMode`; the per-service
modules inline the same check, since `aws/tests/helpers` is a separate module and
cannot be imported across.) The dev-vm test files have **never been compiled** —
`go` is not installed on the machine they were written on, so expect to fix
compile errors on first run.

## 🎯 Features

### AWS

- ✅ **ECS**: Fargate and EC2 launch types with ALB integration
- ✅ **S3**: Object storage patterns
- ✅ **EFS**: Shared file system integration
- ✅ **RDS**: Database scenarios
- ✅ **VPC**: Network infrastructure modules
- ✅ **Monitoring**: CloudWatch dashboards and alarms
- 🟡 **dev-vm**: SSM-brokered Ubuntu dev box, IMDSv2 required (not applied)
- ⬜ **Lambda**: Serverless function scenarios (placeholder)

### GCP

- 🟡 **Network**: VPC, Cloud NAT, IAP firewall rule (not applied)
- 🟡 **dev-vm**: IAP-brokered dev box, OS Login, no external IP (not applied)
- ⬜ **GKE**, **Cloud Run**, **GCS**, **Cloud SQL**

### Azure

- 🟡 **Network**: VNet, NAT Gateway, deny-all NSG (not applied)
- 🟡 **dev-vm**: Bastion-brokered dev box, no public IP on the NIC (not applied)
- ⬜ **AKS**, **Container Instances**, **Blob Storage**, **SQL Database**

### Oracle

- ⬜ **OKE**, **Autonomous Database**, **Object Storage**, **VCN**

## 📚 Documentation

Cross-cloud:

- [Documentation index](docs/README.md)
- [Dev VM break-glass runbook](docs/runbooks/dev-vm-break-glass.md)
- [Git access from the dev VM](docs/guides/dev-vm-git-access.md)
- [Cross-cloud bootstrap and Packer](shared/README.md)
- [The cloud.* command contract](scripts/README.md)
- [Current status and known gaps](.progress.md)
- [Backlog](BACKLOG.md)

AWS-specific (these live under `aws/docs/`, not the root `docs/`):

- [Architecture Overview](aws/docs/architecture/OVERVIEW.md)
- [Quick Start Guide](aws/docs/guides/QUICKSTART.md)
- [Module Development](aws/docs/guides/MODULE_DEVELOPMENT.md)
- [Terraform Style Guide](aws/docs/standards/TERRAFORM_STYLE.md)
- [Tagging Standards](aws/docs/standards/TAGGING_STANDARDS.md)

## 🤝 Contributing

Contributions are welcome! When adding new cloud providers or services:

1. Follow the established directory structure
2. Include comprehensive documentation
3. Add integration tests
4. Update this README, `BACKLOG.md` and `.progress.md`
5. Ensure 12-factor compliance

Scaffold new services with `./scripts/cloud.init.sh` rather than by hand, so they
inherit the repository's conventions and tagging standards.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🗺️ Roadmap

### Phase 1: AWS

- [x] ECS infrastructure and scenarios
- [x] Shared modules (VPC, ALB, IAM)
- [x] Storage scenarios (S3, EFS)
- [x] Database scenarios (RDS)
- [x] Testing framework
- [ ] Lambda scenarios
- [ ] Complete EC2 scenarios

### Phase 2: Multi-cloud foundations

- [x] Per-cloud `shared/modules/` for GCP and Azure
- [x] Cross-cloud dev VM with brokered, non-public access
- [x] Seven `cloud.*` lifecycle commands
- [ ] Remote state backends (S3+DynamoDB / GCS / Azure Storage)
- [ ] Budget alerts per cloud
- [ ] Apply anything to GCP or Azure

### Phase 3: GCP and Azure services

- [ ] GKE basic cluster / AKS cluster setup
- [ ] Cloud Run / Container Instances
- [ ] GCS / Blob Storage
- [ ] Cloud SQL / SQL Database

### Phase 4: Oracle

- [ ] VCN setup
- [ ] OKE cluster
- [ ] Autonomous Database
- [ ] Object Storage

### Phase 5: Multi-Cloud

- [ ] Cross-cloud patterns
- [ ] Unified CLI tool
- [ ] Cost comparison tools
- [ ] Multi-cloud deployment orchestration

## 📝 Migration Notes

### From aws-lab (2026-02-01)

This repository was created by migrating the existing `aws-lab` into a
multi-cloud structure. All AWS content was moved to the `aws/` subdirectory,
maintaining the same organization while preparing for expansion to other cloud
providers.

**What changed**:

- Location: `aws-lab/` → `cloud-lab/aws/`
- Repository name: `aws-lab` → `cloud-lab`
- Structure: Now organized for multi-cloud expansion

**What stayed the same**:

- All AWS infrastructure code
- Module organization
- Testing framework
- Documentation structure
