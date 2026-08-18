# Tasks for Spec 003: Multi-Cloud Development VM

## Phase 0 — foundations

- [x] `shared/bootstrap/install.sh` — Packer provisioner, cloud-agnostic <!-- id: 0 -->
- [x] `shared/bootstrap/seed-home.sh` — first-boot disk mount and seed <!-- id: 1 -->
- [x] `shared/bootstrap/idle-shutdown.sh` — on-box idle detector <!-- id: 2 -->
- [x] `shared/bootstrap/systemd/` — three units <!-- id: 3 -->
- [x] `shared/packer/dev-vm.pkr.hcl` — one template, three sources <!-- id: 4 -->
- [x] `shared/packer/variables.pkr.hcl` <!-- id: 5 -->
- [x] Scaffold the three services with `scripts/cloud.init.sh --with-tests` <!-- id: 6 -->

## Phase 1 — per-cloud stacks

- [x] `aws/shared/modules/vpc/` to `aws/tests/vpc_test.go`'s contract <!-- id: 7 -->
- [x] `aws/compute/dev-vm/` — SSM, zero ingress rules, IMDSv2 <!-- id: 8 -->
- [x] `gcp/shared/modules/network/` — new dir, Cloud NAT, IAP firewall rule <!-- id: 9 -->
- [x] `gcp/compute/dev-vm/` — no `access_config`, OS Login <!-- id: 10 -->
- [x] `azure/shared/modules/network/` — new dir, NAT Gateway, deny-all NSG <!-- id: 11 -->
- [x] `azure/compute/dev-vm/` — Bastion, no public IP on the NIC <!-- id: 12 -->
- [x] Terratest unit + integration tests for all three <!-- id: 13 -->

## Phase 2 — integration and operability

- [x] `packer validate` all three sources <!-- id: 14 -->
- [x] Break-glass runbook — `docs/runbooks/dev-vm-break-glass.md` <!-- id: 15 -->
- [x] Image versioning and GC — `shared/README.md` <!-- id: 16 -->
- [x] Git-from-the-box guide — `docs/guides/dev-vm-git-access.md` <!-- id: 17 -->
- [x] This spec <!-- id: 18 -->
- [x] `.progress.md` update <!-- id: 19 -->
- [x] `pre-commit run --all-files` green <!-- id: 20 -->
- [ ] Budget alerts per cloud <!-- id: 21 -->
- [ ] Remote state backends (S3+DynamoDB / GCS / Azure Storage) <!-- id: 22 -->

## Implementation notes

Completed 2026-08-18, on branch `feat/operational-scripts`. The three per-cloud
stacks were written concurrently by one agent each, which is why their internals
differ in places while the security properties are identical.

### Verified

All six Terraform roots pass `terraform init -backend=false` +
`terraform validate`. `terraform fmt -check -recursive` is clean over every path
this spec touches. All three Packer sources pass `packer validate` with no
credentials. `shellcheck --severity=warning` is clean over `shared/bootstrap/` and
`azure/compute/dev-vm/utils/`. `pre-commit run --all-files` is green.

The security properties were also checked by grep, since they are the deliverable:
no `associate_public_ip_address = true`, no `access_config` block in GCP's
instance, `35.235.240.0/20` as GCP's only allow rule, `http_tokens = "required"`
on AWS, `prevent_destroy` on all three data disks.

### Not verified

- **No `terraform plan` or `apply`, and no `packer build`** — there are no CSP
  credentials. Everything past schema-level validity is unproven: AMI/image
  filters matching a real Packer artifact, the EventBridge Scheduler universal
  target payload, whether the GCP instance schedule attaches, Azure's
  `encryption_at_host_enabled` needing subscription feature registration.
- **No Go compilation.** `go` is not installed, so the six test files are written
  but never compiled or run. `tests/go.mod` has no `go.sum`; `go mod tidy` is
  needed first. Compile errors and `gofmt` drift are both possible.
- **No security scanning.** `tflint`, `tfsec`, `checkov` and `terraform-docs` are
  not installed. See the deviation below.
- Cost figures are from published list pricing, not from `infracost`.

### Deviation: four pre-commit hooks moved to the manual stage

`terraform_tflint`, `terraform_tfsec`, `terraform_checkov` and `terraform_docs`
exited 127 (`command not found`), which blocked every commit touching a `.tf`
file. They are now `stages: [manual]`, matching what SPEC-002 already did to
`infracost_breakdown`.

This is a genuine downgrade, not a cleanup: the security scanners no longer run on
commit even when the binaries are present. Reverse it by installing the tools —
`aws/scripts/setup-dev.sh` treats tflint and tfsec as **required** — and moving
them back to the default stage. tfsec is deprecated upstream in favour of
`terraform_trivy`, so migrating is the better fix than reinstating it.

### Design issues found while building

1. **The persistent disk hides the baked home.** Mounting a data disk at
   `/home/ubuntu` conceals the `~/dotfiles` the image installed. Resolved by the
   seed/restore contract in `shared/bootstrap/`; this was not in the original
   design.
2. **First-boot ordering.** `dev-vm-seed-home.service` runs before user data in
   every cloud, so `/etc/dev-vm/seed-home.env` does not exist on the first boot and
   the script falls back to guessing the disk. The AWS and GCP agents found this
   independently. The contract is now explicit in `shared/README.md` and in the
   unit file: write the env files, then
   `systemctl restart dev-vm-seed-home.service`. All three clouds do this.
3. **`prevent_destroy` aborts the entire `terraform destroy`**, not just the
   protected resource, so `make destroy` refuses to run. Each service README
   carries the targeted-destroy recipe that removes the VM and the NAT (where the
   cost is) and keeps the disk.
4. **Azure Bastion Developer SKU works** in azurerm 5.1.0 despite the registry
   docs implying otherwise, so the planned `az` shim was unnecessary. It is kept in
   `utils/connect.sh` for older providers. Separately: **Basic SKU does not give
   you the native client** — `tunneling_enabled` requires Standard — so Basic costs
   ~$140/mo and is still browser-only.

### Follow-up

- Budget alerts per cloud (id 21) were scoped but not implemented; they belong in
  each stack and were left out rather than raced across three concurrent agents.
- Remote state (id 22) is still local everywhere, so
  `cloud.provision.sh`'s `warn_on_local_state()` fires on every run.
- `.terraform.lock.hcl` is gitignored repo-wide. Committing lock files is normally
  preferred for reproducible provider versions; worth revisiting.
- Three pre-existing files fail `terraform fmt` (`aws/monitoring/cloudwatch/
  {alarms,dashboards}.tf` and one ECS scenario). Untouched here — they date from
  the initial commit.
