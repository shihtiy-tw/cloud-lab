# Plan for Spec 002: Operational Scripts

## 1. Implementation Strategy
Tests will follow the requirements defined in `.opencode/command/*.md`.

## 2. Script Details

### cloud.switch.sh
- Use a `.cloud-context` file to persist state.
- Support `aws`, `gcp`, `azure`, `oracle`.

### cloud.provision.sh
- Detect Terraform backend config based on cloud.
- Support `TF_VAR_` passing.

### cloud.init.sh
- Use templates from `shared/templates` (need to ensure these exist or create them inline/on-the-fly for now).

### cloud.test.sh
- Run `go test -v -timeout 30m`.

## 3. Verification
- Manual execution of `--help` for each script.
- Dry-run of provision logic.
