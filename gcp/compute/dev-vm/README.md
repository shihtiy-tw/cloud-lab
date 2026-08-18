# GCP Compute - Dev VM

A personal development VM on GCP, built from the Packer image in
`shared/packer`, running Ubuntu with the `shihtiy-tw/dotfiles` environment baked
in — and reachable **only** through IAP TCP forwarding.

## The connectivity rule

There is no SSH port on the internet. Not a locked-down one, not one behind an
allowlist: the instance has no external IP address at all.

That is enforced by three things, each of which is one line away from being
false:

| Property | Where | What breaks it |
|----------|-------|----------------|
| No external IP | `infrastructure/main.tf`, `network_interface` | Adding an `access_config` block. That block is what assigns a public address; its absence *is* the requirement. |
| SSH ingress from IAP only | `gcp/shared/modules/network`, `google_compute_firewall.iap_ssh` | Widening `source_ranges` beyond `35.235.240.0/20`, above all to `0.0.0.0/0`. |
| Keys from IAM, not metadata | `enable-oslogin = "TRUE"` in instance metadata | Turning OS Login off, which re-enables metadata SSH keys as a standing back door. |

`tests/unit/dev_vm_test.go` asserts all three by reading the source, so they fail
in CI with no credentials rather than in a review someone skims.

Why IAP rather than a bastion or a VPN: IAP authorises the caller against IAM
*before* a packet reaches the instance, needs no agent on the box, no
always-on host to patch and pay for, and no keys to distribute or rotate.
Revoking someone is an IAM change, not a key hunt.

## Connecting

```bash
# The only supported way in. Also emitted as the `ssh_command` output.
gcloud compute ssh <instance-name> --tunnel-through-iap --zone <zone> --project <project-id>

# Port-forward something running on the box (a dev server, a k8s API) over the
# same tunnel -- again with no public listener anywhere.
gcloud compute start-iap-tunnel <instance-name> 3000 --local-host-port=localhost:3000 \
  --zone <zone> --project <project-id>
```

The box stops itself when idle, so the usual first step is starting it:

```bash
gcloud compute instances start <instance-name> --zone <zone> --project <project-id>
```

Prerequisites on your workstation: `gcloud`, an authenticated account
(`gcloud auth login`), and membership in `var.developer_principals`. With an
empty `developer_principals` list nobody can log in — there is no external IP and
no metadata key to fall back on.

## Day one of CSP access — checklist

Run through this once per project. Most of it is not Terraform's job, and
skipping a step produces a stack that applies cleanly and then does not work.

1. **Enable the APIs.**

   ```bash
   gcloud services enable compute.googleapis.com iap.googleapis.com \
     oslogin.googleapis.com logging.googleapis.com monitoring.googleapis.com \
     --project <project-id>
   ```

2. **Confirm your own IAM.** You need enough to create the stack
   (`roles/compute.admin`, `roles/iam.serviceAccountAdmin`,
   `roles/resourcemanager.projectIamAdmin` or equivalent). This is the "admin
   lives on the human's identity" half of the design — the VM's own service
   account deliberately has none of it.

3. **Grant the Compute Engine service agent instance admin**, once per project,
   or the auto-stop schedule silently never fires:

   ```bash
   PROJECT_NUMBER=$(gcloud projects describe <project-id> --format='value(projectNumber)')
   gcloud projects add-iam-policy-binding <project-id> \
     --member="serviceAccount:service-${PROJECT_NUMBER}@compute-system.iam.gserviceaccount.com" \
     --role="roles/compute.instanceAdmin.v1"
   ```

4. **Build the image** (see `shared/packer/README` notes in `shared/README.md`).
   The Packer build also needs a subnetwork with an IAP firewall rule, because the
   builder has no public IP either.

5. **Turn on Data Access audit logs** for the services that record access — see
   [Audit](#audit) below. They are off by default, and they are the log that
   answers "who logged into this box?".

6. **Set `terraform.tfvars`** from `infrastructure/terraform.tfvars.example`. At
   minimum `project_id` and `developer_principals`.

7. **Apply, then connect.**

   ```bash
   make plan CLOUD=gcp SERVICE=compute/dev-vm ENV=dev
   make provision CLOUD=gcp SERVICE=compute/dev-vm ENV=dev
   ```

8. **Verify the properties rather than trusting them.** `has_external_ip` must be
   `false`, and `iap_firewall_source_ranges` must equal whatever
   `var.iap_source_ranges` resolves to — by default the published IAP range,
   `["35.235.240.0/20"]`. It can never be `0.0.0.0/0`: the network module's
   variable validation rejects that value, so the check below is a second line of
   defence rather than the only one.

## Layout

| Path                | Purpose                                  |
| ------------------- | ---------------------------------------- |
| `infrastructure/` | Terraform for the VM, its disk, its identity and its access |
| `infrastructure/templates/` | The metadata startup script that configures the image's boot scripts |
| `tests/`          | Terratest unit (no credentials needed) and integration tests |
| `utils/`          | Helper scripts for this service          |

The VPC lives in `gcp/shared/modules/network` and is consumed as a module.

## How this fits the shared image

The image is cloud-agnostic on purpose: `shared/bootstrap/seed-home.sh` and
`shared/bootstrap/idle-shutdown.sh` read their configuration from env files under
`/etc/dev-vm/`, and each cloud's Terraform writes them. Here that is the metadata
startup script in `infrastructure/templates/`.

The one binding worth internalising:

```text
attached_disk.device_name = "devhome"
        ↓  GCE guest environment
/dev/disk/by-id/google-devhome
        ↓  written to /etc/dev-vm/seed-home.env as DATA_DISK_DEVICE
seed-home.sh mounts it at /home/ubuntu and seeds it from /opt/dev-vm/home-seed
```

Rename the `device_name` without updating the path and first boot cannot find the
disk. `seed-home.sh` fails loudly on a configured-but-absent device rather than
guessing, which is the behaviour you want.

**First-boot ordering caveat.** `dev-vm-seed-home.service` runs
`Before=sysinit.target`; GCE runs the metadata startup script much later, from
`google-startup-scripts.service`. So on the very first boot the seeding has
already run against the image's defaults, where `DATA_DISK_DEVICE` is unset and
the script falls back to "the first blank disk" — correct here, since the home
disk is the only non-boot disk. The startup script then restarts the unit with
the authoritative config, which is idempotent and safe on a mounted, seeded home.
That restart is what makes the behaviour deterministic instead of dependent on the
fallback.

## Cost

The VM is the small number. The network is the big one.

| Item | Rough monthly cost | Runs while the VM is stopped? |
|------|--------------------|-------------------------------|
| **Cloud NAT gateway** | **~$32** plus data processing | **Yes** |
| `e2-standard-4` instance | ~$0.13/hour, so ~$8 at 60 hours of use | No |
| 100 GB pd-balanced home disk | ~$10 | Yes |
| 50 GB pd-balanced boot disk | ~$5 | Yes, unless the instance is destroyed |
| Flow logs, NAT logs, Cloud Logging | cents at these volumes | Subnet logs, no |

Say it plainly: **Cloud NAT is ~$32/month and it is the dominant standing cost
once the VM auto-stops.** A box used 60 hours a month costs more in NAT than in
compute. Two levers:

- `enable_cloud_nat = false` if the box only ever needs Google APIs.
  `private_ip_google_access` is free and covers those. It will not run
  `apt install`.
- Destroy the stack between stretches of use (below). The home disk survives.

Auto-stop is two independent mechanisms, because either alone has a gap:

- **On-box idle timer** (`idle_shutdown_enabled`, `idle_minutes`) reacts to actual
  idleness and refuses to kill a running build, a tmux session or a live
  container. It cannot help if the box wedges.
- **Instance schedule policy** (`auto_stop_enabled`, `vm_stop_schedule`) is a
  clock that always fires. `vm_start_schedule` is empty by default: a box that
  starts itself every morning bills for the mornings you did not use it.

## Tearing it down

`google_compute_disk.home` sets `lifecycle { prevent_destroy = true }`, so a
plain `terraform destroy` **refuses to run at all** rather than skipping that one
resource. That is intended — the disk holds every uncommitted branch on the box —
but it means the teardown has a recipe:

```bash
cd infrastructure

# Destroy the expensive parts, keep the disk. This is the normal "I am done for a
# few weeks" path: it removes Cloud NAT (~$32/mo) and the instance, and leaves
# ~$10/mo of disk holding your work.
terraform destroy \
  -target=google_compute_instance.dev_vm \
  -target=module.network.google_compute_router_nat.main \
  -target=module.network.google_compute_router.nat
```

Re-applying later recreates the instance, reattaches the same disk, and
`seed-home.sh` finds it already seeded and leaves it alone.

To remove everything including the data — the only path that loses work:

```bash
terraform state rm google_compute_disk.home   # drops Terraform's protection
terraform destroy
gcloud compute disks delete <disk-name> --zone <zone>   # now unmanaged
```

## Recovery / break-glass

No SSH means a broken IAP path is a lockout. In rough order of what to try:

1. **Is the box running?** Idle shutdown and the schedule policy both stop it.
   `gcloud compute instances start ...`.
2. **Is your IAM still there?** `developer_principals` drives both bindings;
   removing yourself from that list revokes your own access at the next
   connection. Check with
   `gcloud compute instances get-iam-policy <name> --zone <zone>`.
3. **Is the tunnel reachable?** Run
   `gcloud compute start-iap-tunnel <name> 22 --zone <zone>` to isolate the
   tunnel from the SSH layer. A failure here is IAP, IAM or the firewall rule; a
   failure only in `gcloud compute ssh` is OS Login or sshd.
4. **Is sshd alive?** If the box booted but sshd did not, the tunnel connects and
   the login fails. See the serial console below.

### Serial console

The last resort, and **off by default** (`enable_serial_console = false`):

```bash
# Enable for the duration of the recovery, then turn it back off.
terraform apply -var enable_serial_console=true
gcloud compute connect-to-serial-port <instance-name> --zone <zone> --project <project-id>
terraform apply -var enable_serial_console=false
```

Off by default is a deliberate tradeoff, and worth understanding rather than
flipping past. The serial console **bypasses the entire access model**: it does
not go through IAP, it is not filtered by any firewall rule, it does not use OS
Login, and it will hand you a root console on a box whose disk holds your SSH
keys and cloud credentials. It is guarded only by
`roles/compute.instanceAdmin` on the project and, if configured,
`compute.disableSerialPortAccess` at the org level. Leaving it on permanently
would be a standing second door that none of the controls above cover — so it is
a door you open, use, and close, and the `serial_console_enabled` output exists
so you can see whether you forgot.

If the serial console is also unavailable, the disk is still intact: detach it
and mount it on a throwaway VM.

```bash
gcloud compute instances detach-disk <instance-name> --disk <disk-name> --zone <zone>
```

## Audit

IAP and OS Login access is recorded in Cloud Audit Logs, which is the answer to
"who logged into this box and when?" — but **Data Access audit logs are off by
default** and are where most of the useful detail lives. Admin Activity logs
(instance create/start/stop, IAM changes) are always on and free.

Enable Data Access logging for `iap.googleapis.com`,
`oslogin.googleapis.com` and `compute.googleapis.com` in IAM → Audit Logs, or in
the project's IAM policy. Then:

```bash
# Tunnel authorisations
gcloud logging read \
  'protoPayload.serviceName="iap.googleapis.com" AND resource.type="gce_instance"' \
  --project <project-id> --limit 20

# Instance start/stop, including the schedule policy's own actions
gcloud logging read \
  'protoPayload.methodName=~"instances.(start|stop)"' \
  --project <project-id> --limit 20
```

Two more sources worth knowing about, both enabled by this stack: Firewall Rules
Logging on the IAP allow rule and on the explicit deny-all (GCP's *implied* deny
cannot be logged, which is why the explicit rule exists), and VPC flow logs at
50% sampling — the only record of what a box with no public IP talked to.

## Usage

```bash
# Plan
make plan CLOUD=gcp SERVICE=compute/dev-vm ENV=dev

# Apply
make provision CLOUD=gcp SERVICE=compute/dev-vm ENV=dev

# Test (unit tests need no credentials)
make test CLOUD=gcp SERVICE=compute/dev-vm

# Security scan
make security CLOUD=gcp SERVICE=compute/dev-vm

# Regenerate the Terraform docs block below
make docs CLOUD=gcp SERVICE=compute/dev-vm
```

Validate without credentials:

```bash
terraform -chdir=infrastructure init -backend=false -input=false
terraform -chdir=infrastructure validate
```

## A note on labels

`local.common_tags` follows `aws/docs/standards/TAGGING_STANDARDS.md`, which uses
CamelCase keys and values like `platform.team`. GCP labels reject both: keys and
values allow only lowercase letters, digits, `-` and `_`, up to 63 characters,
and the rejection happens at apply time. So `local.common_labels` is a sanitised
form (`CostCenter` → `cost-center`, `platform.team` → `platform-team`) and the
raw tag set stays available as the `common_tags` output for anything that needs
the canonical values. The networking resources take neither — GCP has no labels
on networks, subnetworks, routers or firewall rules — so the module folds them
into `description` instead of dropping them.

## Inputs and outputs

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
