---
id: SPEC-003
title: Multi-Cloud Development VM
status: active
owner: cloud-lab
version: 1.0.0
last_updated: 2026-08-18
---

# Spec 003: Multi-Cloud Development VM

## 1. Overview

This specification defines a personal development VM in AWS, GCP and Azure,
running Ubuntu LTS with [`shihtiy-tw/dotfiles`](https://github.com/shihtiy-tw/dotfiles)
pre-installed, reachable only through each cloud's native brokered access path.

It is the repository's first multi-cloud service. Before it, `gcp/`, `azure/` and
`oracle/` contained no `.tf` files and root `shared/` was empty, so the layout it
establishes is the pattern later services follow.

## 2. Goals

- One golden image per cloud, built from a single shared provisioner.
- Terminal access with **no SSH port reachable from the internet**, in any cloud.
- Admin capability on the human identity; the VM's own identity stays scoped.
- Work survives `terraform destroy`.
- Standing cost near zero when the VM is not in use.

## 3. Non-Goals

- No managed Kubernetes (EKS/GKE/AKS). The ask was Kubernetes *tooling*;
  `kind`/`k3d` run on the box.
- No Oracle Cloud. `oracle/` exists and OCI Bastion is the analogue, but it is
  out of scope.
- No remote IDE, no `rsync`, no SSH port-forwarding.

## 4. Access Requirements

The access requirement is the reason this spec exists, stated as the user gave
it: *do not use SSH open to the public network; use the cloud-native secure way
for connection.*

| Cloud | Broker | Internet-facing ingress | Broker cost |
|-------|--------|-------------------------|-------------|
| AWS | SSM Session Manager | none at all | $0 |
| GCP | IAP TCP forwarding | tcp:22 from `35.235.240.0/20` only | $0 |
| Azure | Bastion (Developer SKU) | none; Bastion is out-of-band | $0 |

## 5. Requirements

- The VM MUST NOT have a public IP address in any cloud.
- Inbound MUST be limited to the broker's path, or absent entirely.
- AWS instances MUST enforce IMDSv2 (`http_tokens = "required"`).
- All disks MUST be encrypted.
- The VM identity MUST NOT hold admin/owner/contributor on the account.
- The data disk MUST carry `prevent_destroy` and MUST mount at `/home/ubuntu`.
- The image MUST be pinned; an unpinned lookup silently forces replacement.
- Each cloud MUST have both a scheduled stop and on-box idle shutdown.
- Each cloud MUST have a documented break-glass path, because no SSH means a
  broken broker is a lockout.
- Unit tests MUST pass with no cloud credentials; integration tests MUST be
  guarded so `go test -short ./...` stays green.

## 6. Layout

Each cloud owns its own tree; only cloud-agnostic assets live at the root, per
SPEC-001's definition of root `shared/` as "cross-cloud modules and patterns".

```text
shared/bootstrap/          install.sh, seed-home.sh, idle-shutdown.sh, systemd/
shared/packer/             dev-vm.pkr.hcl (3 sources), variables.pkr.hcl
aws/shared/modules/vpc/    implements the contract aws/tests/vpc_test.go declares
gcp/shared/modules/network/
azure/shared/modules/network/
{aws,gcp,azure}/compute/dev-vm/{infrastructure,tests,utils,scenarios}
```

## 7. Constraints at time of writing

No CSP credentials exist, so this specification is satisfied by static
verification only: `terraform validate -backend=false`, `terraform fmt`,
`packer validate`, `shellcheck`, and offline unit tests. `terraform apply`,
`packer build` and `make cost-estimate` are deferred to
[`quickstart.md`](./quickstart.md)'s day-one checklist.
