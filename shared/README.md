# shared/

Cross-cloud assets. Anything that is specific to one provider belongs in that
provider's own tree (`aws/shared/modules/`, `gcp/shared/modules/`,
`azure/shared/modules/`), not here.

| Path | Purpose |
|------|---------|
| `bootstrap/` | Scripts baked into the dev-vm image. Cloud-agnostic: no cloud CLI calls, no metadata service reads. |
| `packer/` | One Packer template with three sources that all run the same provisioner. |

## bootstrap/

| File | Runs | Purpose |
|------|------|---------|
| `install.sh` | Once, during `packer build`, as root | Clones `shihtiy-tw/dotfiles` to `~/dotfiles` at a pinned ref, runs `make install && make init && make cloud`, sets zsh as the login shell, installs the units below, and writes `/etc/dev-vm-build.json`. |
| `seed-home.sh` | Every boot, from `dev-vm-seed-home.service` | Mounts the persistent data disk at the user's home and seeds it from the image on first boot. |
| `idle-shutdown.sh` | Every 5 min, from `dev-vm-idle-shutdown.timer` | Powers the VM off after a period with no session and no active work. |

### The home-seeding contract

These two scripts implement one design that is easy to break by editing either
half alone.

The image bakes `~/dotfiles` into `/home/ubuntu`. The lifecycle design also keeps
`/home/ubuntu` on a **separate disk that survives `terraform destroy`**. Mounting
that disk over the home directory would hide everything the image installed.

So `install.sh` copies the finished home to `/opt/dev-vm/home-seed` — outside the
mount point — and `seed-home.sh` restores it into the volume the first time it
finds it unseeded, marking it with `.dev-vm-seeded`. Later boots mount the volume
and leave it alone, which is what makes the disk persistent rather than merely
re-imaged.

Two safety properties worth preserving if you touch `seed-home.sh`:

- It formats **only** a disk with no filesystem at all. An existing filesystem is
  someone's work and is never reformatted.
- It writes `/etc/fstab` entries by UUID, never by device path. nvme and scsi
  enumeration order is not stable across reboots, and a wrong entry here is an
  unbootable VM.

### Configuration

Both boot scripts read env files under `/etc/dev-vm/`, which each cloud's
Terraform writes via user_data / metadata / custom_data. That is how the data
disk device path — which differs per cloud — reaches `seed-home.sh`:

| Cloud | `DATA_DISK_DEVICE` |
|-------|--------------------|
| AWS | `/dev/nvme1n1` (`/dev/xvdf` on Xen instance types) |
| GCP | `/dev/disk/by-id/google-devhome` |
| Azure | `/dev/disk/azure/scsi1/lun0` |

## packer/

One template, three sources, one provisioner. The only real difference between
clouds is how Packer connects to the build instance — and since the requirement
is that no SSH port is ever exposed to the internet, that applies to build
instances too:

| Source | Connection | Public IP on builder |
|--------|-----------|----------------------|
| `amazon-ebs` | `ssh_interface = "session_manager"` | No |
| `googlecompute` | `use_iap` + `omit_external_ip` + `use_internal_ip` | No |
| `azure-arm` | direct SSH, NSG-scoped to `azure_build_allowed_cidr` | **Yes, ephemeral** |

Azure is the exception and it is a plugin limitation, not an oversight: setting
`virtual_network_name` requires Packer *itself* to run from a host inside that
VNet, so a workstation-driven private build is impossible. The build VM is
short-lived, holds no data, and is destroyed; set `azure_build_subnet_id` and run
Packer from inside the VNet to close even that gap. Either way the **dev VM**
Terraform creates never gets a public IP, which is the actual requirement.

### Commands

```bash
cd shared/packer
packer init .

# Validate. Works with no credentials; GCP needs a project id because there is
# no defensible default for one.
packer validate -only='dev-vm.amazon-ebs.dev-vm' .
packer validate -only='dev-vm.azure-arm.dev-vm' .
packer validate -only='dev-vm.googlecompute.dev-vm' -var gcp_project_id=validate-only .

# Build one cloud
packer build -only='dev-vm.amazon-ebs.dev-vm' -var-file=aws.pkrvars.hcl .
```

### Two defaults that are deliberate

- **`ubuntu_release = "24.04"`, not 26.04.** 26.04 LTS shipped 2026-04-23, and
  the third-party apt repositories the dotfiles installer depends on (Docker,
  HashiCorp, Kubernetes) routinely lag a new release by months. Building on 26.04
  before they publish a `resolute` pocket fails partway through. Flip the variable
  once they have — the point of a Packer pipeline is that trying costs one build.
- **`architecture = "amd64"`, not arm64.** arm64 is 20-40% cheaper, but some tools
  the installer fetches publish amd64-only release assets. Worth trying; not worth
  defaulting to before it has been proven.

Prefer passing a commit SHA for `dotfiles_ref`. `develop` is a moving target, so
two builds a week apart produce different images from identical inputs. The
resolved SHA is always recorded in `/etc/dev-vm-build.json` on the image.
