# cloud-lab - Claude Context

See [AGENTS.md](./AGENTS.md) for full context.

## Rules

- **Never `git push` without explicit approval.** Committing locally is fine;
  publishing is not. This applies to `git push`, opening or updating PRs, and
  anything else that leaves this machine. Ask first, every time — approval for one
  push is not approval for the next.

## Claude-Specific Notes

- Multi-cloud infrastructure lab (AWS, GCP, Azure, Oracle)
- Migrated from aws-lab on 2026-02-01
- Terraform-first approach for all cloud providers
- Comprehensive testing with Terratest
