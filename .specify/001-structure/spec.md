---
id: SPEC-001
title: Project Structure
status: active
owner: cloud-lab
version: 1.0.0
last_updated: 2026-02-07
---

# Spec 001: Project Structure

## 1. Overview
This specification defines the directory structure for `cloud-lab`, ensuring support for multiple cloud providers (AWS, GCP, Azure, Oracle) within a single monorepo.

## 2. Goals
- Standardize structure across all cloud providers.
- Ensure separation of concerns (infrastructure vs. scenarios vs. tests).
- Enable automated tooling to discover services.

## 3. Directory Structure

### 3.1 Root Level
- `aws/`: AWS-specific resources.
- `gcp/`: GCP-specific resources.
- `azure/`: Azure-specific resources.
- `oracle/`: Oracle-specific resources.
- `shared/`: Cross-cloud modules and patterns.
- `scripts/`: Operational scripts.
- `.opencode/`: Command documentation.
- `.specify/`: Specifications and plans.

### 3.2 Cloud Provider Structure
Each provider directory (`aws/`, `gcp/`, etc.) MUST contain:
- `compute/`
- `storage/`
- `database/`
- `networking/`
- `security/`
- `monitoring/`

### 3.3 Service Structure
Each service directory (e.g., `aws/compute/ecs`) MUST contain:
- `infrastructure/`: Terraform code.
- `scenarios/`: Example configurations.
- `tests/`: Terratest files.
- `README.md`: Documentation.

## 4. Compliance
- All directories MUST be lower-case kebab-case.
- All Terraform files MUST be in `infrastructure/` or `scenarios/`.
