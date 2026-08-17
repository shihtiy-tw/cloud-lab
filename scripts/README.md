# Operational Scripts

Implementation of [SPEC-002: Operational Scripts](../.specify/002-scripts/spec.md).
These are the executables behind every `Makefile` target; the behavioural
contract for each one lives in [`.opencode/command/`](../.opencode/command/).

## Commands

| Script                | Purpose                                             | Make target(s)              |
| --------------------- | --------------------------------------------------- | --------------------------- |
| `cloud.switch.sh`     | Switch the active cloud provider context            | `aws` `gcp` `azure` `oracle` `status` |
| `cloud.provision.sh`  | Terraform init/validate/plan/apply/destroy          | `provision` `plan` `destroy` |
| `cloud.init.sh`       | Scaffold a new service                              | `init`                      |
| `cloud.test.sh`       | Run Go/Terratest suites                             | `test` `test-all`           |
| `cloud.security.sh`   | Run tfsec, checkov, and trivy                       | `security` `security-all`   |
| `cloud.docs.sh`       | Generate terraform-docs output                      | `docs` `docs-all`           |
| `cloud.cost.sh`       | Report actual spend, estimate planned spend         | `cost` `cost-estimate`      |

`lib/common.sh` holds the shared logging, validation, context, and path
resolution helpers. It is sourced, never executed.

## Conventions

Every script:

- accepts `--help` and `--version`
- takes `--cloud aws|gcp|azure|oracle`, falling back to `CLOUD_PROVIDER` in
  `.cloud-context` when the flag is omitted
- writes all diagnostics to stderr, leaving stdout for data you may want to pipe
- returns the exit codes below

### Exit codes

Per [`.specify/002-scripts/data-model.md`](../.specify/002-scripts/data-model.md):

| Code | Meaning                                       |
| ---- | --------------------------------------------- |
| 0    | Success                                       |
| 1    | General error                                 |
| 2    | Invalid usage or arguments                    |
| 3    | Missing dependency (terraform, go, tfsec, …)  |
| 4    | Security check failed                         |

Missing third-party tools are always exit 3 with an install hint, never a
silent skip.

## Getting started

```bash
# 1. Set the active context (writes the git-ignored .cloud-context)
make aws                    # or: ./scripts/cloud.switch.sh --cloud aws --profile dev --region us-west-2
make status

# 2. Load it into your own shell, if you want the env vars directly
eval "$(./scripts/cloud.switch.sh --show --export)"

# 3. Plan a stack
make plan CLOUD=aws SERVICE=compute/ecs/infrastructure/cluster ENV=dev
```

## Two things that surprise people

### Service paths point at a single Terraform root

`aws/compute/ecs` contains 16 separate Terraform roots (one per scenario, plus
the infrastructure components). `--service compute/ecs` is therefore ambiguous,
and `cloud.provision.sh` lists the candidates rather than guessing which stack
to touch:

```bash
make plan CLOUD=aws SERVICE=compute/ecs/infrastructure/cluster ENV=dev
```

`cloud.security.sh`, `cloud.docs.sh`, and `cloud.test.sh` do not have this
constraint — they walk every Terraform root or Go module below the path.

### `--env` does not select a Terraform workspace

Most `aws/` stacks in this repo set `region = terraform.workspace`, so the
workspace name *is* the AWS region. A workspace called `dev` fails with
`Invalid AWS Region: dev`. So `--env` only:

- selects `<env>.tfvars` when that file exists, and
- passes `environment=<env>` when the stack declares that variable

Use `--workspace` to control the workspace explicitly:

```bash
./scripts/cloud.provision.sh --cloud aws \
  --service compute/ecs/infrastructure/vpc --env dev \
  --workspace us-east-1 --plan-only
```

`cloud.provision.sh` warns when it detects the `region = terraform.workspace`
convention so this is visible at run time.

## Safety model

`cloud.provision.sh` always plans to a file and applies that exact plan, so what
gets applied is what you reviewed.

| Action       | Requirements                                                         |
| ------------ | -------------------------------------------------------------------- |
| non-prod apply | Interactive prompt, or `--auto-approve`                            |
| prod apply     | `--confirm`, plus a prompt unless `--auto-approve`                 |
| destroy        | `--confirm`, plus typing an exact confirmation phrase              |
| prod destroy   | `--confirm` and the phrase; `--auto-approve` cannot skip it        |

Confirmation prompts refuse to run when stdin is not a terminal rather than
assuming consent.

## Tooling

Required per command; all are checked at run time with an install hint:

| Tool             | Needed by                                |
| ---------------- | ---------------------------------------- |
| `terraform`      | `provision`, `cost --estimate` (binary plans) |
| `go`             | `test`                                   |
| `tfsec`, `checkov`, `trivy` | `security` (at least one)      |
| `terraform-docs` | `docs`                                   |
| `infracost`      | `cost --estimate`                        |
| provider CLI     | `switch` verification, `cost`            |

`aws/scripts/setup-dev.sh` installs most of these.

## Development

```bash
# Lint (matches the pre-commit gate)
shellcheck --severity=warning scripts/cloud.*.sh scripts/lib/common.sh

# Format
shfmt -i 2 -ci -bn -sr -w scripts/
```

`.shellcheckrc` sets `external-sources=true` so `lib/common.sh` is followed when
each script is checked on its own, which is how pre-commit invokes shellcheck.

## Coverage limits

Worth knowing before you rely on these:

- **Cost reporting is fully normalised for AWS only.** Cost Explorer results are
  aggregated into a ranked table with percentages. GCP, Azure, and Oracle
  queries are issued through their own CLIs and their native output is passed
  through unchanged, because the response shape varies with account setup.
- **GCP cost reporting needs a BigQuery billing export.** There is no Cost
  Explorer equivalent; pass `--billing-table` or set
  `GCP_BILLING_EXPORT_TABLE`.
- **`--min-severity` does not apply to checkov.** The open-source build has no
  severity filter, so it reports every failed check. The summary says so rather
  than implying the filter was applied.
- **Tag breakdowns are approximated** for GCP, Azure, and Oracle (grouped by
  project, resource group, and compartment respectively). Each logs a warning
  naming the substitution.
