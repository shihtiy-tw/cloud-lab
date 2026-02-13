---
id: SPEC-002
title: Operational Scripts
status: active
owner: cloud-lab
version: 1.0.0
last_updated: 2026-02-07
---

# Spec 002: Operational Scripts

## 1. Overview
This specification defines the required shell scripts for platform operations, aligning with the `Makefile` and `.opencode` command documentation.

## 2. Goals
- Implement missing scripts referenced in `.opencode`.
- Ensure scripts are CSP-aware (AWS, GCP, Azure, Oracle).
- Provide a consistent CLI experience.

## 3. Required Scripts (in `scripts/`)

| Script | Purpose |
|--------|---------|
| `cloud.switch.sh` | Switch between cloud providers and environments. |
| `cloud.provision.sh` | Wrapper for Terraform init/plan/apply/destroy. |
| `cloud.init.sh` | Scaffold new services. |
| `cloud.test.sh` | Run tests (Terratest). |
| `cloud.security.sh` | Run security scans (tfsec, checkov). |
| `cloud.docs.sh` | Generate documentation. |
| `cloud.cost.sh` | Estimate and analyze costs. |

## 4. Requirements
- Scripts MUST be executable.
- Scripts MUST support `--help` flag.
- Scripts MUST return non-zero exit code on failure.
- Scripts MUST use environment variables for configuration where appropriate.
