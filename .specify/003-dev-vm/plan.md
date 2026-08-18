# Plan for Spec 003: Multi-Cloud Development VM

## 1. Implementation Strategy

Sequential foundations, then one agent per cloud in parallel, then integration.
The three clouds are independent trees, so they genuinely parallelise once the
shared image contract is fixed.

Services are scaffolded with the repo's own generator rather than by hand, so
they inherit its conventions:

```bash
./scripts/cloud.init.sh --cloud aws   --category compute --name dev-vm --with-tests
./scripts/cloud.init.sh --cloud gcp   --category compute --name dev-vm --with-tests
./scripts/cloud.init.sh --cloud azure --category compute --name dev-vm --with-tests
```

Keep the generator's `TerraformDir: "../../infrastructure"` and its module path
`github.com/org/cloud-lab/<cloud>/<category>/<name>/tests`.

## 2. Phases

### Phase 0 — foundations

Everything else depends on these, so they are sequential.

1. `shared/bootstrap/` — `install.sh` (the Packer provisioner, cloud-agnostic),
   `seed-home.sh` (first-boot disk mount and seed), `idle-shutdown.sh`, and the
   three systemd units.
2. `shared/packer/` — one template, three sources, one provisioner.
3. Scaffold the three services so the per-cloud agents start from identical trees.

### Phase 1 — three clouds in parallel

Each agent owns exactly one cloud and writes its network module,
`compute/dev-vm/infrastructure/`, `compute/dev-vm/tests/`, and the service README.

| Agent | Writes |
|-------|--------|
| AWS | `aws/shared/modules/vpc/` to `aws/tests/vpc_test.go`'s contract; NAT, scoped instance profile, IMDSv2 required, EC2 from AMI, EBS data disk with `prevent_destroy`, `aws_scheduler_schedule` stop, SSM session logging. Security group with **no ingress rules at all**. |
| GCP | `gcp/shared/modules/network/`; Cloud NAT, IAP firewall rule for `35.235.240.0/20`, OS Login, minimal service account, `google_compute_resource_policy` schedule, persistent disk, instance with **no `access_config`**. |
| Azure | `azure/shared/modules/network/`; VNet with `default_outbound_access_enabled = false` + NAT Gateway, Bastion Developer (with `az` fallback in `utils/`), user-assigned managed identity, managed data disk, `azurerm_dev_test_global_vm_shutdown_schedule`, **no public IP on the NIC**. |

### Phase 2 — integration and operability

Sequential again, after the fan-out.

1. Reconcile the three Packer sources; `packer validate` per source.
2. Break-glass runbook —
   [`docs/runbooks/dev-vm-break-glass.md`](../../docs/runbooks/dev-vm-break-glass.md).
3. Image versioning and GC notes (AMI deregister + snapshot delete, GCP image
   family deprecation, gallery version pruning).
4. Budget alerts, `make docs`, and the `gh auth login` device-flow note for
   pushing from a box with no SSH agent forwarding.
5. This spec, `.progress.md`, and a repo-wide `pre-commit run --all-files`.

## 3. Design decisions

| Decision | Choice |
|----------|--------|
| Access | Terminal only. SSM / IAP / Bastion. No remote IDE, no port-forward. |
| Bootstrap | Packer golden images from the start, not boot-time cloud-init. |
| VM identity | Scoped. Admin lives on the human identity and is assumed on demand. |
| Lifecycle | Persistent data disk at `/home/ubuntu` with `prevent_destroy`. |
| Auto-stop | Both a cloud-side schedule and on-box idle detection. |
| Ubuntu | 24.04 default, 26.04 behind a variable. See `research.md` §3. |
| Architecture | amd64 default, arm64 behind a variable. |

## 4. Verification

No CSP credentials exist, so verification is static.

```bash
for d in aws/shared/modules/vpc gcp/shared/modules/network azure/shared/modules/network \
         aws/compute/dev-vm/infrastructure gcp/compute/dev-vm/infrastructure \
         azure/compute/dev-vm/infrastructure; do
  terraform -chdir="$d" init -backend=false -input=false && \
  terraform -chdir="$d" validate
done

terraform fmt -recursive -check
shellcheck shared/bootstrap/*.sh
packer init shared/packer/ && packer validate -only='dev-vm.amazon-ebs.dev-vm' shared/packer/
pre-commit run --all-files
```

The security requirements are greppable, so check them as part of review rather
than trusting a later apply:

```bash
# No public IP on any dev VM
! grep -rn 'associate_public_ip_address *= *true' aws/compute/dev-vm/
! grep -rn 'access_config'                        gcp/compute/dev-vm/

# GCP's only :22 ingress is the IAP range
grep -rn '35.235.240.0/20' gcp/

# IMDSv2 required
grep -rn 'http_tokens *= *"required"' aws/compute/dev-vm/

# Data disk protected
grep -rln 'prevent_destroy' aws/compute/dev-vm/ gcp/compute/dev-vm/ azure/compute/dev-vm/
```

Unit tests must pass offline (`terraform.Init` + `Validate` only). Integration
tests are written but guarded, so `go test -short ./...` stays green.

## 5. Deferred until CSP access exists

`terraform plan` (provider auth for data sources), `packer build`,
`make provision`, `make cost-estimate`, and the remote state backends
(S3+DynamoDB / GCS / Azure Storage) — so `cloud.provision.sh`'s
`warn_on_local_state()` keeps firing until then.

The live checklist is in [`quickstart.md`](./quickstart.md) §6 so it is not
re-derived later.
