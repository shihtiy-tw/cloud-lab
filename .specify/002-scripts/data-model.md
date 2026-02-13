# Data Model: Operational Scripts

## 1. Command Schema

Scripts comply with the following interface:

```bash
./scripts/{command}.sh --cloud {provider} [options]
```

## 2. Configuration Schema (`.cloud-context`)

The context file matches this key-value format:

```env
CLOUD_PROVIDER=aws|gcp|azure|oracle
# AWS
AWS_PROFILE=string
AWS_DEFAULT_REGION=string
# GCP
CLOUDSDK_CORE_PROJECT=string
CLOUDSDK_COMPUTE_REGION=string
# Azure
AZURE_SUBSCRIPTION_ID=string
# Oracle
OCI_CLI_PROFILE=string
OCI_CLI_REGION=string
```

## 3. Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General Error |
| 2 | Invalid Usage / Arguments |
| 3 | Missing Dependency (e.g., terraform not found) |
| 4 | Security Check Failed |
