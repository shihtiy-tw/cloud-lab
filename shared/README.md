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

| Cloud | `DATA_DISK_DEVICE` | Coupled to |
|-------|--------------------|------------|
| AWS | `/dev/nvme1n1` (`/dev/xvdf` on Xen instance types) | the volume attachment's `device_name`; Nitro renames it |
| GCP | `/dev/disk/by-id/google-devhome` | the attached disk's `device_name = "devhome"` |
| Azure | `/dev/disk/azure/scsi1/lun0` | the data disk attachment's `lun = 0` |

Each value is coupled to a Terraform attribute in the right-hand column. A
mismatch does not error — `seed-home.sh` silently falls back to guessing — so keep
the two ends commented in the per-cloud Terraform.

### First-boot ordering: the one thing each cloud must do

`dev-vm-seed-home.service` deliberately runs before any login is possible, which
is *earlier than user data runs in every cloud*. On the very first boot
`/etc/dev-vm/seed-home.env` therefore does not exist yet, and the script falls
back to "first unmounted, unformatted disk".

So the contract for each cloud's boot script is two steps, not one:

```bash
# 1. write the config
install -d -m 0755 /etc/dev-vm
cat > /etc/dev-vm/seed-home.env <<'EOF'
TARGET_USER=ubuntu
HOME_SEED_DIR=/opt/dev-vm/home-seed
FS_LABEL=devhome
DATA_DISK_DEVICE=<per-cloud value from the table above>
EOF

# 2. re-run the unit now that it can be configured properly
systemctl restart dev-vm-seed-home.service
```

The restart is safe on every boot: the unit is `Type=oneshot` and `seed-home.sh`
leaves an already-seeded, already-mounted home alone. Do **not** solve this by
reordering the unit to wait for user data — that would allow a login to land in
the unseeded home and then have the disk mounted out from under it.

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

### Image lifecycle and cleanup

Every build leaves an artifact behind that bills monthly and that nothing deletes
for you. A 50 GB image is roughly $2-4/mo in each cloud, so a year of weekly
builds is a real line item — and the snapshot, not the image, is usually what
keeps charging.

| Cloud | Artifact | The part people forget |
|-------|----------|------------------------|
| AWS | AMI + its EBS snapshot | Deregistering the AMI does **not** delete the snapshot. It keeps billing silently. |
| GCP | Image in a family | Superseding an image does not delete it. Deprecate, then delete. |
| Azure | Gallery image *version* | Each version is replicated to every region in `replication_regions`, and you pay per replica. |

```bash
# AWS -- deregister, then delete the snapshot it referenced
SNAP=$(aws ec2 describe-images --image-ids "$AMI" \
  --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' --output text)
aws ec2 deregister-image --image-id "$AMI"
aws ec2 delete-snapshot --snapshot-id "$SNAP"

# List candidates by the tags the template applies
aws ec2 describe-images --owners self \
  --filters 'Name=tag:component,Values=dev-vm' \
  --query 'sort_by(Images,&CreationDate)[].[ImageId,Name,CreationDate]' --output table

# GCP -- deprecate first so anything still referencing the family gets warned,
# then delete after the grace period
gcloud compute images deprecate "$IMAGE" --state DEPRECATED --replacement "$NEW_IMAGE"
gcloud compute images delete "$IMAGE"
gcloud compute images list --filter='labels.component=dev-vm' --format='table(name,creationTimestamp)'

# Azure -- delete the version, not the image definition
az sig image-version delete --gallery-name cloudlab --gallery-image-definition dev-vm \
  --resource-group cloud-lab-images --gallery-image-version 0.1.0
az sig image-version list --gallery-name cloudlab --gallery-image-definition dev-vm \
  --resource-group cloud-lab-images -o table
```

Do not delete the image a live VM was created from until that VM is gone. AWS and
Azure both keep running instances alive without their source image, but a
`terraform apply` that re-reads the image data source will fail — and on Azure a
gallery version is required to stay present while any VM references it.

Keep the last two or three; the point of pinning is being able to roll back to
the image that worked.
