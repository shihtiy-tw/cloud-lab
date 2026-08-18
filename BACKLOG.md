# cloud-lab Backlog

**Purpose**: Future work queue and idea parking lot

**Last Updated**: 2026-08-18

Status markers: `[x]` done and verified, `[~]` written but never applied (no
credentials for that cloud yet), `[ ]` not started. See `.progress.md` for the
detail behind each.

---

## High Priority (Next Sprint)

- [ ] Unblock the toolchain gate — `go`, `tflint`, `tfsec`, `checkov`,
      `terraform-docs` and `infracost` are all absent, which is why five
      pre-commit hooks sit on the manual stage and why no Go test has ever been
      compiled. `aws/scripts/setup-dev.sh` installs them. Highest verification
      gain for the least effort.
- [ ] Remote state backends (S3+DynamoDB / GCS / Azure Storage) — all six
      Terraform roots are on local state and `cloud.provision.sh` warns on every
      run
- [ ] Budget alerts per cloud — scoped in SPEC-003 but not implemented. NAT is
      ~$32/mo per cloud and **does not stop when the VM does**, so "stopped" is
      not "free"
- [~] GCP VPC foundational infrastructure — `gcp/shared/modules/network/` exists
      (VPC, subnet, Cloud NAT, IAP firewall rule) and validates; never applied
- [~] Azure VNet foundational infrastructure — `azure/shared/modules/network/`
      exists (VNet, NAT Gateway, deny-all NSG,
      `default_outbound_access_enabled = false`) and validates; never applied
- [ ] Compile the Terratest suites — 7 test files across 4 modules, none ever
      built, no `go.sum` anywhere. `go mod tidy && go vet ./...` first
- [ ] Decide the fate of the three orphaned `vk/*` branches — they share no git
      history with `main` (`git merge-base` exits 1) so they cannot be merged;
      either cherry-pick content across or delete them

---

## Medium Priority (This Quarter)

- [ ] GCP GKE basic cluster scenario
- [ ] Azure AKS basic cluster scenario
- [ ] Oracle VCN foundational infrastructure
- [ ] Oracle OKE basic cluster scenario
- [ ] Oracle dev-vm via OCI Bastion — the fourth cloud's analogue of SPEC-003,
      deliberately out of scope there
- [ ] Migrate `terraform_tfsec` to `terraform_trivy` — tfsec is deprecated
      upstream, so migrating beats reinstating it
- [ ] Return the four manual-stage hooks to the default stage once their binaries
      are installed (`terraform_tflint`, `terraform_docs`, `terraform_tfsec`,
      `terraform_checkov`)
- [ ] Populate `shared/templates/` so `cloud.init.sh --template` has something to
      copy
- [ ] Fix `region = terraform.workspace` in the 26 `aws/` files that do it — it is
      why `--env` cannot select a workspace, and new stacks must not copy it
- [ ] Fill the empty root `tests/` and `examples/` directories, or drop them
- [ ] Normalise cost reporting beyond AWS — other providers currently pass native
      CLI output straight through
- [ ] Repo-wide markdownlint sweep (~440 violations across 88 files); the gate
      only covers files as they are touched
- [ ] Reconsider gitignoring `.terraform.lock.hcl` — committing lock files is
      normally preferred for reproducible provider versions
- [ ] `terraform fmt` three stragglers from the initial commit
      (`aws/monitoring/cloudwatch/{alarms,dashboards}.tf` and one ECS scenario)
- [ ] Create cross-cloud patterns (VPC peering equivalents)
- [ ] Multi-cloud cost comparison dashboard
- [ ] Unified monitoring setup (Prometheus/Grafana)
- [ ] Write `specs/001-csp-foundations/`, which is currently an empty directory

---

## Low Priority (Someday/Maybe)

- [ ] Multi-cloud Terraform workspace strategy
- [ ] Cross-cloud disaster recovery patterns
- [ ] Serverless comparison (Lambda/Functions/Cloud Functions)
- [ ] Container registry unification
- [ ] GitOps for multi-cloud
- [ ] arm64 dev-vm variant (Graviton/Axion/Cobalt, ~20-40% cheaper) — the
      `architecture` variable exists; some dotfiles tools may be amd64-only
- [ ] NAT instance (fck-nat, ~$3/mo) as a lab-grade substitute for AWS NAT Gateway
- [ ] Try Ubuntu 26.04 "Resolute" for the dev-vm — default is 24.04 because
      third-party apt repos lag a new release; Packer makes it a cheap experiment
- [ ] Run Packer from inside the Azure VNet (container instance or self-hosted
      runner) so even the *build* VM needs no public IP

---

## Ideas / Parking Lot

- 💡 Cloud cost anomaly detection
- 💡 Automated cloud drift detection
- 💡 Multi-region deployment patterns
- 💡 Service mesh across clouds
- 💡 Unified IAM abstraction layer
- 💡 A CI job that runs the manual-stage security hooks, so a missing local
      binary stops being the only thing between a commit and a scan

---

## Archived / Won't Do

- **EKS/GKE/AKS clusters as part of the dev VM.** The SPEC-003 ask was Kubernetes
  *tooling*, not a managed cluster; `kind`/`k3d` run on the box for free.
- **SSH exposed to the internet, in any cloud.** Every access path is brokered
  (SSM / IAP / Bastion) by design. Reintroducing a public port 22 would defeat
  the point of SPEC-003.
