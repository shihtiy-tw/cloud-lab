# Quickstart: Operational Scripts

## 1. Setup

Ensure you have the required CLIs installed:
- `terraform`
- `aws` (AWS CLI)
- `gcloud` (Google Cloud SDK)
- `az` (Azure CLI)
- `oci` (Oracle CLI)

## 2. Common Workflows

### Switching Context
```bash
./scripts/cloud.switch.sh --cloud aws --profile staging
```

### Provisioning Infrastructure
```bash
./scripts/cloud.provision.sh --cloud aws --service compute/ecs --env dev
```

### Running Tests
```bash
./scripts/cloud.test.sh --cloud aws --service compute/ecs
```

## 3. Getting Help

All scripts support `--help`:

```bash
./scripts/cloud.provision.sh --help
```
