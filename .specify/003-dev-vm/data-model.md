# Data Model: Multi-Cloud Development VM

## 1. Image contract

The golden image is produced by `shared/packer/dev-vm.pkr.hcl` and carries a
build stamp so "what is on this box" is answerable without guessing.

`/etc/dev-vm-build.json`:

```json
{
  "dotfiles_repo": "https://github.com/shihtiy-tw/dotfiles.git",
  "dotfiles_ref": "develop",
  "dotfiles_sha": "resolved at build time",
  "ubuntu_release": "24.04",
  "architecture": "amd64",
  "target_user": "ubuntu",
  "build_time": "ISO-8601"
}
```

Paths baked into the image:

| Path | Purpose |
|------|---------|
| `/home/ubuntu/dotfiles` | Clone location. Load-bearing — upstream `make/init.sh` resolves configs from it. |
| `/opt/dev-vm/home-seed/` | Pristine copy of the home directory, outside the data-disk mount point. |
| `/usr/local/sbin/dev-vm-seed-home` | First-boot disk mount and seed. |
| `/usr/local/sbin/dev-vm-idle-shutdown` | Idle detector, run by a systemd timer. |

## 2. Instance configuration contract

Terraform writes two env files via user_data / metadata / custom_data. The
image's systemd units read them, so the image needs no rebuild to retune.

`/etc/dev-vm/seed-home.env`:

```env
TARGET_USER=ubuntu
HOME_SEED_DIR=/opt/dev-vm/home-seed
FS_LABEL=devhome
DATA_DISK_DEVICE=<per-cloud, see below>
```

`/etc/dev-vm/idle-shutdown.env`:

```env
ENABLED=true
IDLE_MINUTES=30
CHECK_INTERVAL_MINUTES=5      # must match the timer's OnUnitActiveSec
LOAD_THRESHOLD=0.5
IGNORE_CONTAINERS=false
```

## 3. Data disk device paths

Data disks surface under different paths per cloud. Each value is coupled to a
Terraform attribute, and a mismatch fails silently at boot:

| Cloud | `DATA_DISK_DEVICE` | Coupled to |
|-------|--------------------|------------|
| AWS | `/dev/nvme1n1` | `aws_volume_attachment.device_name` (Nitro renames it) |
| GCP | `/dev/disk/by-id/google-devhome` | the attached disk's `device_name = "devhome"` |
| Azure | `/dev/disk/azure/scsi1/lun0` | the data disk attachment's `lun = 0` |

With no configured device, `seed-home.sh` falls back to the first unmounted,
unformatted whole disk. That is a convenience for a single-data-disk VM, not a
guarantee.

## 4. Filesystem state

| Path | Meaning |
|------|---------|
| `/dev/disk/by-label/devhome` | The data disk, once formatted. Mounted at `/home/ubuntu` by UUID in `/etc/fstab`. |
| `/home/ubuntu/.dev-vm-seeded` | Marker. Present means "already seeded, leave it alone". |
| `/var/lib/dev-vm/idle-counter` | Consecutive idle minutes. Reset on any activity. |

`seed-home.sh` formats **only** when `blkid` reports no filesystem type. Any
existing filesystem is someone's work and is never reformatted.

## 5. Terraform module contracts

`aws/shared/modules/vpc/` — the contract `aws/tests/vpc_test.go` already declares:

| Direction | Names |
|-----------|-------|
| in | `project_name`, `environment`, `vpc_cidr`, `tags` |
| out | `vpc_id`, `vpc_cidr`, `private_subnet_ids`, `public_subnet_ids` |

`gcp/shared/modules/network/`:

| Direction | Names |
|-----------|-------|
| in | `project_name`, `environment`, `project_id`, `region`, `vpc_cidr`, `labels` |
| out | `network_id`, `network_name`, `subnetwork_id`, `subnetwork_name`, `subnet_cidr` |

`azure/shared/modules/network/`:

| Direction | Names |
|-----------|-------|
| in | `project_name`, `environment`, `location`, `resource_group_name`, `vnet_cidr`, `tags` |
| out | `vnet_id`, `vnet_name`, `subnet_id`, `subnet_name`, `subnet_cidr`, `nat_gateway_id` |

Azure's region variable is `location`, not `region` — that is what
`scripts/cloud.init.sh` generates, and it matches the provider.

## 6. Access identities

| Cloud | VM identity (scoped) | Human identity (admin) |
|-------|----------------------|------------------------|
| AWS | instance profile: SSM core + CloudWatch write | `ssm:StartSession` on the instance |
| GCP | service account: logging/monitoring write | `roles/iap.tunnelResourceAccessor` + `roles/compute.osLogin` |
| Azure | user-assigned managed identity, scoped roles | `Virtual Machine User Login` + Bastion reader |

The split is the point: the VM cannot escalate, and admin is assumed on demand by
the human.
