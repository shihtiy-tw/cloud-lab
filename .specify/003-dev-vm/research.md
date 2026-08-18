# Research: Multi-Cloud Development VM

## 1. The dotfiles repository already does the heavy lifting

`shihtiy-tw/dotfiles@develop` exposes `make install` (core tools), `make init`
(symlinks configs), and a composite `make cloud` = `aws` + `gcp` + `azure` +
`kubernetes`. Those sub-targets install exactly the brokered-access clients this
design needs: `make aws` the **session-manager-plugin**, `make gcp` the **GKE
auth plugin**, `make azure` **kubelogin**, `make kubernetes`
kubectl/helm/k9s/kustomize.

Two consequences:

- It must be cloned to exactly `~/dotfiles`. `make/init.sh` resolves config paths
  from there, so a different location breaks symlinking.
- It ships `make test-install` and `make test-symlinks`. We reuse those as the
  post-provision assertion instead of writing our own checks.

`make install` is documented as unattended and destructive (it removes distro
Docker packages and installs Docker CE). That is fine inside a Packer build and
is a strong argument against running it at every boot.

## 2. Bootstrap timing: boot-time vs. image

- **Boot-time (cloud-init)**: no build pipeline, but every VM start pays 15-40
  minutes of compiling and downloading, and a transient apt failure produces a
  half-configured box.
- **Golden image (Packer)**: one build, then sub-minute boots and a byte-identical
  environment in all three clouds.
- **Decision**: **Packer**, from the start. The cost is one template; the payoff is
  that "why is my VM different today" stops being a question.

## 3. Ubuntu release

Ubuntu 26.04 LTS "Resolute Raccoon" released 2026-04-23 and is the newest LTS.
It is also only ~4 months old, and third-party apt repositories (Docker,
HashiCorp, Kubernetes) routinely lag a new release — a missing `resolute` pocket
fails the dotfiles install partway through.

**Decision**: default `ubuntu_release = "24.04"`, keep it a variable. Packer makes
trying 26.04 cost one build rather than a broken VM.

## 4. Private Packer builds

| Builder | Private build? | Mechanism |
|---------|----------------|-----------|
| `amazon-ebs` | yes | `ssh_interface = "session_manager"`, no public IP, no ingress rule |
| `googlecompute` | yes | `use_iap` + `omit_external_ip` + `use_internal_ip` |
| `azure-arm` | **no** | `virtual_network_name` requires Packer itself to run inside that VNet |

Azure is the exception. A laptop-driven private build is not possible, so the
*build* VM gets an ephemeral public IP scoped to the builder's egress CIDR and is
destroyed minutes later. The *dev* VM never gets a public IP, which is the actual
requirement. Hardening path: run Packer from inside the VNet (container instance
or self-hosted runner).

## 5. Azure default outbound access is retired

For API versions after 2026-03-31, new VNet subnets have no implicit internet
egress. Without an explicit path the Azure VM cannot reach apt or GitHub at all,
so a **NAT Gateway is mandatory**, and subnets set
`default_outbound_access_enabled = false` explicitly so behaviour does not depend
on which API version the provider happens to use.

## 6. Azure Bastion SKU

`azurerm_bastion_host` documents `ip_configuration` as required, while the
Developer SKU instead takes `virtual_network_id` and needs no
`AzureBastionSubnet`. **Resolved: azurerm 5.1.0 accepts Developer SKU.** The
schema declares `ip_configuration` as an optional list, and the provider binary
carries the validation string `` `virtual_network_id` is required when `sku` is
`Developer` ``. No `az` shim is needed; one remains in
`azure/compute/dev-vm/utils/connect.sh` for anyone pinned to an older provider.

SKU economics, which are not what the SKU names suggest:

| SKU | Cost | Native `az network bastion ssh` |
|-----|------|--------------------------------|
| Developer | free | no — browser only |
| Basic | ~$140/mo | **no — still browser only** |
| Standard | ~$140/mo + scale units | yes |

`tunneling_enabled` (and `ip_connect_enabled`, `file_copy_enabled`) are rejected
by the provider below Standard. So paying for Basic buys nothing over Developer
for this use case — Developer is the default, and Standard is the only upgrade
worth making. Developer is region-limited and serves one VM at a time.

## 7. `aws/tests/vpc_test.go` is aspirational

It targets `../shared/modules/vpc`, but `aws/shared/modules/vpc/` held only a
`.gitkeep` — the module was never written. The test expects inputs
`project_name`, `environment`, `vpc_cidr`, `tags` and outputs `vpc_id`,
`vpc_cidr`, `private_subnet_ids`, `public_subnet_ids`. The real VPC Terraform at
`aws/compute/ecs/infrastructure/vpc` matches neither contract.

**Decision**: the dev VM needs a VPC anyway, so implement the module to the
contract the existing test already declares rather than rewrite the test.

`aws/compute/ecs/infrastructure/vpc` remains a useful reference for shape
(public/private subnets, IGW, EIP, NAT GW, route tables) — but it sets
`region = terraform.workspace`, and new stacks must not copy that. See SPEC-002's
deviation note for why that convention is a problem.

## 8. Cost shape

Because the VMs auto-stop, the dominant standing cost is **egress
infrastructure, not compute**: a managed NAT is roughly $32/mo per cloud, ~$96/mo
with all three standing. In preference order:

1. Destroy the stack when a cloud is not in use — the data disk is
   `prevent_destroy`, so work survives.
2. AWS: substitute a NAT instance (fck-nat pattern, ~$3/mo) for lab use.
3. Accept the NAT cost only in the cloud being actively used.

"Stopped" is not "free". Budget alerts per cloud are part of the design, not an
afterthought.

## 9. Home directory on a persistent disk

Mounting a persistent disk at `/home/ubuntu` conflicts with baking `~/dotfiles`
into the image: the mount hides everything the image installed.

**Decision**: `install.sh` stashes a pristine copy at `/opt/dev-vm/home-seed`
(outside the mount point) and `seed-home.sh` restores it the first time the volume
is seen empty. Later boots mount the volume untouched, which is what makes the
disk persistent rather than merely re-imaged.

## 10. Break-glass

With no SSH, a broken SSM agent, IAP config or Bastion is a hard lockout. EC2
Serial Console, GCP serial-port access and Azure boot diagnostics are enabled or
documented up front. This is the recommendation most likely to eventually matter.
