# AZURE Compute - Dev vm

> Scaffolded by `scripts/cloud.init.sh` on 2026-08-18. Replace the TODOs.

## Overview

TODO: what this service provisions and when to use it.

## Layout

| Path                | Purpose                                  |
| ------------------- | ---------------------------------------- |
| `infrastructure/` | Terraform for the service itself         |
| `scenarios/`      | Runnable end-to-end usage examples       |
| `tests/`          | Terratest unit and integration tests     |
| `utils/`          | Helper scripts for this service          |

## Usage

```bash
# Plan
make plan CLOUD=azure SERVICE=compute/dev-vm ENV=dev

# Apply
make provision CLOUD=azure SERVICE=compute/dev-vm ENV=dev

# Test
make test CLOUD=azure SERVICE=compute/dev-vm

# Security scan
make security CLOUD=azure SERVICE=compute/dev-vm

# Regenerate the Terraform docs block below
make docs CLOUD=azure SERVICE=compute/dev-vm
```

## Inputs and outputs

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->

## Cost

TODO: note the cost drivers and roughly what an idle stack costs.
