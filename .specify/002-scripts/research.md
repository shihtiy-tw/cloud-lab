# Research: Operational Scripts

## 1. Context
We need a unified interface to manage multi-cloud operations. `make` is good for shortcuts, but shell scripts provide the logic.

## 2. Analysis of Tools

### Wrappers vs. Direct CLI
- **Direct CLI**: Users run `terraform`, `aws`, `gcloud` directly.
- **Wrappers**: Scripts abstract the differences.
- **Decision**: Use **Wrappers** (`cloud.*.sh`) to normalize common tasks (provision, test) while allowing direct CLI usage when needed.

### Language Choice
- **Bash**: Native, no dependencies, good for glue code.
- **Python/Go**: Better for complex logic, but requires runtime/compilation.
- **Decision**: **Bash** for these operational scripts to minimize dependencies and ensure easy editing.

## 3. Precedents
- `kubernetes-lab` uses strict Makefiles.
- `microservice-platform` uses `.opencode` commands.
- We align with `.opencode` patterns to support the "Agentic" workflow.
