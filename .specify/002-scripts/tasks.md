# Tasks for Spec 002: Operational Scripts

- [x] Create `scripts/` directory if not exists <!-- id: 0 -->
- [x] Implement `scripts/cloud.switch.sh` <!-- id: 1 -->
- [x] Implement `scripts/cloud.provision.sh` <!-- id: 2 -->
- [x] Implement `scripts/cloud.init.sh` <!-- id: 3 -->
- [x] Implement `scripts/cloud.test.sh` <!-- id: 4 -->
- [x] Implement `scripts/cloud.security.sh` <!-- id: 5 -->
- [x] Implement `scripts/cloud.docs.sh` <!-- id: 6 -->
- [x] Implement `scripts/cloud.cost.sh` <!-- id: 7 -->
- [x] Make all scripts executable (`chmod +x`) <!-- id: 8 -->

## Implementation notes

Completed 2026-08-18. See [`scripts/README.md`](../../scripts/README.md) for the
CLI contract.

Beyond the task list:

- `scripts/lib/common.sh` (mode 644, sourced not executed) holds the shared
  logging, validation, `.cloud-context`, and path-resolution helpers. It was not
  in the spec but every command needs the same exit-code vocabulary.
- `.gitignore` now excludes `.cloud-context`; it can hold account and
  subscription ids.
- `.shellcheckrc` gained `external-sources=true`. `source-path=SCRIPTDIR` was
  inert without it, so `lib/common.sh` was never followed and every helper it
  defines looked unassigned (SC2154) when a script was checked on its own —
  which is exactly how pre-commit invokes shellcheck.

### Deviation from the spec

`.opencode/command/cloud.provision.md` describes `--env` as selecting a
Terraform workspace. That is wrong for this repo: 26 files under `aws/` set
`region = terraform.workspace`, so the workspace name *is* the AWS region, and a
workspace named `dev` fails with `Invalid AWS Region: dev`. Only 5 stacks declare
`variable "environment"` at all.

So `--env` selects `<env>.tfvars` and passes `environment=<env>` only when the
stack declares that variable. Workspace selection moved to an explicit
`--workspace` flag, and the script warns when it detects the convention.

### Follow-up

- `.opencode/command/cloud.provision.md` should be updated to match the
  `--env` / `--workspace` split above.
- `shared/templates/` does not exist, so `cloud.init.sh --template` has nothing
  to copy from. It fails with a clear message listing what is available.
