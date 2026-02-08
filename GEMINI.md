# cloud-lab - Gemini Context

See [AGENTS.md](./AGENTS.md) for full context.

## Gemini-Specific Notes

- Multi-cloud repository: AWS (active), GCP/Azure/Oracle (planned)
- Use `.specify/*` for spec-driven development
- Terraform is the primary IaC tool across all clouds
- When working on cloud-specific code, navigate to `<cloud-provider>/` directory
- Follow 12-factor principles for all automation scripts
