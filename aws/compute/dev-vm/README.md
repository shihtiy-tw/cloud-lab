# AWS Compute - dev-vm

A personal Ubuntu development VM built from the shared Packer image
(`shared/packer/dev-vm.pkr.hcl`), reachable **only** through SSM Session Manager.

There is no SSH port open to the internet, and that is not implemented by
narrowing port 22 to a home IP address. It is implemented by there being nothing
to narrow:

| Property | How |
|----------|-----|
| No public IP | Private subnet, `associate_public_ip_address = false`, asserted by an apply-time postcondition |
| No inbound rules | The security group has **zero** ingress rules. Session Manager is outbound-only: the agent dials the regional endpoint over 443 |
| No SSH key | No `key_name` on the instance — there is no key to leak |
| IMDSv2 required | `http_tokens = "required"`, hop limit 1, so an SSRF on the box cannot lift the instance credentials |
| Encrypted at rest | Root and data volumes both encrypted, CMK optional |
| Least privilege | The instance role gets `AmazonSSMManagedInstanceCore`, write access to its own log groups, and read-only `Describe*`. Nothing else |
| Persistent home | `/home/ubuntu` is a separate EBS volume with `prevent_destroy` |
| Auto-stop | On-box idle timer, plus an EventBridge Scheduler hard stop as a backstop |
| Auditable sessions | An SSM `Session` document streams every session transcript to CloudWatch Logs |

Admin privileges deliberately live on **your** identity, not on the machine. Assume
an admin role from inside the shell when you need one, so the privilege exists for
the length of a command and is recorded in CloudTrail against a person. An instance
profile with admin would make every process on the box — and every dependency the
dotfiles installer pulls — an administrator.

## Layout

| Path | Purpose |
|------|---------|
| `infrastructure/` | Terraform for the VM, its VPC, IAM, schedule and session logging |
| `infrastructure/templates/` | cloud-init user_data that configures the image's boot scripts |
| `tests/unit/` | `init` + `validate` only; runs with no credentials |
| `tests/integration/` | Applies for real and asserts the security properties over SSM |
| `utils/` | Helper scripts for this service |

## Usage

```bash
# 1. Build the image once (see shared/README.md)
cd shared/packer && packer build -only='dev-vm.amazon-ebs.dev-vm' -var-file=aws.pkrvars.hcl .

# 2. Pin the AMI it produced
jq -r '.builds[-1].artifact_id' shared/packer/manifest.json   # "<region>:<ami-id>"

# 3. Configure and apply
cp aws/compute/dev-vm/infrastructure/terraform.tfvars.example \
   aws/compute/dev-vm/infrastructure/terraform.tfvars
make plan      CLOUD=aws SERVICE=compute/dev-vm ENV=dev
make provision CLOUD=aws SERVICE=compute/dev-vm ENV=dev

# 4. Connect
eval "$(terraform -chdir=aws/compute/dev-vm/infrastructure output -raw ssm_start_session_command)"
```

### Pin the AMI

`var.ami_id` takes precedence over the `data aws_ami` lookup, and setting it is
strongly preferred. The lookup filters on the `image_version` tag rather than
merely "most recent", but two builds of the same version still produce different
AMI ids — so an unpinned lookup means that the next time anyone rebuilds the image,
`terraform plan` proposes replacing your VM. Replacement is safe (the home volume
is not Terraform's to delete) but it should be a decision, not a surprise.

## Connecting

```bash
# A logged shell. --document-name is what attaches the session preferences that
# turn on the transcript; without it you get an unlogged shell.
aws ssm start-session \
  --target "$(terraform output -raw instance_id)" \
  --document-name "$(terraform output -raw ssm_session_document_name)"

# Reach a dev server on the box without any inbound rule
aws ssm start-session --target "$(terraform output -raw instance_id)" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'

# SSH-over-SSM, if you want scp/rsync and VS Code Remote. Still no open port:
# the transport is the SSM tunnel. Add to ~/.ssh/config:
#   Host i-* mi-*
#     ProxyCommand sh -c "aws ssm start-session --target %h \
#       --document-name AWS-StartSSHSession --parameters portNumber=%p"
```

Prerequisites on your workstation: the AWS CLI v2 and the
[Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).
Sessions land as `ubuntu` in the persistent home, with zsh, because the session
document sets `runAsDefaultUser` and a `shellProfile`.

### What is logged

Every session transcript streams to the CloudWatch log group in
`session_log_group_name` — command and output, continuously, so a session that is
killed mid-way still leaves evidence. CloudTrail records only that a session
started, by whom, against which instance; the transcript is what makes the session
auditable. Set `enable_session_log_bucket = true` to also archive transcripts to
S3 (versioned, encrypted, expiring after a year) when you need them to outlive the
log group's retention.

## Cost

Roughly, `us-east-1`, on-demand, `t3.large`:

| Item | Running | Stopped |
|------|---------|---------|
| Instance (t3.large) | ~$0.083/hr, ~$60/mo if never stopped | $0 |
| Root volume, 50 GB gp3 | ~$4/mo | ~$4/mo |
| Home volume, 100 GB gp3 | ~$8/mo | ~$8/mo |
| **NAT gateway** | **~$32/mo** + $0.045/GB | **~$32/mo** |
| CloudWatch Logs | cents | cents |

**The NAT gateway is ~$32/month and it is the dominant standing cost once the VM
auto-stops.** It bills by the hour whether or not anything is using it, so a box
you touch twice a week still costs more in NAT than in compute. It is not optional
while the VM exists: apt, GitHub and container registries all need general internet
egress, which VPC interface endpoints cannot provide.

The way to avoid paying for it is to tear the stack down when you are done:

```bash
make destroy CLOUD=aws SERVICE=compute/dev-vm ENV=dev
```

That removes the NAT gateway, the instance and the VPC. **The home volume
survives** — `lifecycle { prevent_destroy = true }` makes Terraform refuse to
delete it — so `make provision` later gives you the same home directory back at
the cost of a reboot. Rebuilding the stack is a couple of minutes; a lost home
directory is not.

Terraform will report an error at the end of a destroy because of that protection.
That is the protection working. The stack destroy still needs the volume out of
the way, so:

```bash
# Intentionally retiring the volume too
cd aws/compute/dev-vm/infrastructure
terraform state rm aws_ebs_volume.home     # Terraform stops managing it
terraform destroy                          # the rest of the stack goes
aws ec2 delete-volume --volume-id vol-...  # deliberate, manual, irreversible
```

Take a snapshot first if the volume holds anything you have not pushed.

Also worth doing on day one: activate the `Project`, `Environment` and `CostCenter`
cost allocation tags in the Billing console and put a small AWS Budgets alarm on
the account. This stack is cheap to leave running by accident and there is no other
signal that you have.

## Recovery / break-glass

There is exactly one door, so plan for it being stuck. Symptoms and remedies, in
the order to try them:

**The instance is stopped.** The idle timer or the schedule did its job.

```bash
aws ec2 start-instances --instance-ids "$(terraform output -raw instance_id)"
```

**`start-session` says the target is not connected.** The SSM agent has not
registered. Check the agent's own view first:

```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$(terraform output -raw instance_id)"
```

Almost always one of three things: the NAT gateway is gone (no egress, so the agent
cannot dial out), the instance profile lost `AmazonSSMManagedInstanceCore`, or the
agent crashed. The first two are Terraform problems. For the third, a stop/start
restarts the agent and is worth trying before anything else.

**The agent is genuinely broken, or the box will not finish booting.** This is the
lockout case: no SSH exists to fall back on. Use **EC2 Serial Console**, which
attaches to the instance's serial port through the EC2 control plane and needs no
network on the guest at all:

```bash
# One-time, per region, and it needs account-level permission granted first
aws ec2 enable-serial-console-access
aws ec2 get-serial-console-access-status

# Then: EC2 console -> the instance -> Connect -> EC2 serial console
```

Two things must be true *before* you need it, so do them while the box is healthy:

1. **Set a password for `ubuntu`.** Serial console gives you a getty login prompt,
   and cloud images ship with the password locked. From a working SSM session:
   `sudo passwd ubuntu`, then store the password in your password manager. Without
   this, the serial console connects and you can do nothing with it.
2. **Know that it is a real console.** Kernel messages, GRUB, single-user mode —
   this is where you fix a broken `/etc/fstab` entry or a wedged
   `dev-vm-seed-home.service`.

If all else fails, the home volume is the only thing that matters: `terraform state
rm aws_ebs_volume.home`, destroy, recreate the stack, and attach the old volume by
importing it or snapshotting and restoring it. The data was never on the instance.

**Boot diagnostics without a shell:**

```bash
aws ec2 get-console-output --instance-id "$(terraform output -raw instance_id)" --latest
```

## Day one of CSP access — checklist

The order matters: several steps are cheap before the VM exists and awkward after.

- [ ] **Root account**: MFA on, no access keys, never used again. Create an admin
      role or IAM Identity Center user for yourself and use that.
- [ ] **Region**: decide one and set `region` in `terraform.tfvars`. Everything
      here is regional; a VM in the wrong region is a slow VM.
- [ ] **Account-level EBS encryption by default**: turn it on
      (`aws ec2 enable-ebs-encryption-by-default`). This stack encrypts its own
      volumes explicitly, but the default catches everything you create by hand
      later.
- [ ] **IMDSv2 by default**: set the account attribute so instances created outside
      this stack get it too
      (`aws ec2 modify-instance-metadata-defaults --http-tokens required`).
- [ ] **Session Manager plugin** installed on your workstation, and confirm you can
      `aws sts get-caller-identity`.
- [ ] **Serial console access enabled** for the region, and a password set on the
      `ubuntu` user once the VM is up. See the recovery section — this is the only
      break-glass path.
- [ ] **Cost guardrails**: activate cost allocation tags, create an AWS Budgets
      alarm, and note that the NAT gateway bills whether the VM is running or not.
- [ ] **Build the image**: `packer build -only='dev-vm.amazon-ebs.dev-vm'`. It needs
      a private subnet with egress and an instance profile with
      `AmazonSSMManagedInstanceCore`, because the build itself connects over SSM.
      The first stack apply creates a usable subnet for that.
- [ ] **Pin `ami_id`** from `shared/packer/manifest.json`.
- [ ] **Apply**, then read the assertions back:
      `terraform output public_ip_assertion ingress_rule_assertion imdsv2_assertion`.
- [ ] **Open a session** with `--document-name`, confirm you land in
      `/home/ubuntu` as `ubuntu` with the dotfiles present, and confirm
      `findmnt --target /home/ubuntu` shows the data volume rather than the root
      disk.
- [ ] **Check the transcript arrived** in the CloudWatch log group. If sessions are
      not being logged, the audit story is missing and you will not notice later.
- [ ] **Remote state**: this stack currently uses local state, deliberately (no
      backend exists yet). Before it holds anything you care about, move it to S3
      with DynamoDB or S3 native locking.

## Inputs and outputs

<!-- BEGIN_TF_DOCS -->
`terraform-docs` is not installed in this environment, so this section is
hand-maintained; `make docs CLOUD=aws SERVICE=compute/dev-vm` will regenerate it.

**Key inputs** (see `infrastructure/variables.tf` for all of them and why each
default is what it is):

| Name | Default | Notes |
|------|---------|-------|
| `project_name` | — | Required. |
| `environment` | — | Required: `dev`/`staging`/`test`/`prod`. |
| `region` | `us-east-1` | A real variable, not `terraform.workspace`. |
| `ami_id` | `""` | Pin it. Overrides the lookup. |
| `ami_image_version` | `0.1.0` | The `image_version` tag to select. |
| `instance_type` | `t3.large` | Must match `architecture`. |
| `data_volume_size` | `100` | The disk that survives destroy. |
| `data_disk_device` | `/dev/nvme1n1` | `/dev/xvdf` on Xen instance types. |
| `idle_minutes` | `30` | On-box idle shutdown threshold. |
| `auto_stop_cron` | `cron(0 21 ? * MON-FRI *)` | Scheduler backstop. |
| `enable_session_log_bucket` | `false` | S3 archive for transcripts. |
| `kms_key_arn` | `""` | CMK for EBS and logs; empty uses AWS-managed keys. |
| `egress_cidr_blocks` | `["0.0.0.0/0"]` | The only rule the SG has. |

**Outputs**: `instance_id`, `ssm_start_session_command`,
`ssm_port_forward_command_example`, `ssm_session_document_name`, `data_volume_id`,
`data_volume_device`, `public_ip_assertion`, `ingress_rule_assertion`,
`imdsv2_assertion`, `security_group_id`, `instance_role_arn`,
`session_log_group_name`, `session_log_bucket`, `auto_stop_schedule`, `ami_id`,
`availability_zone`, `instance_private_ip`, `vpc_id`, `nat_public_ips`, `name`,
`common_tags`.
<!-- END_TF_DOCS -->

## Tests

```bash
# No credentials needed: init + validate only
cd aws/compute/dev-vm/tests && go test -v ./unit/...

# Real resources, real money. Asserts no public IP, no ingress, IMDSv2, encrypted
# volumes, then runs the dotfiles' own `make test-install` and `make test-symlinks`
# on the box over `aws ssm send-command`.
cd aws/compute/dev-vm/tests && go test -v -timeout 45m ./integration/...
```

The integration test also asserts that `terraform destroy` *fails* while the home
volume is protected, because a destroy that succeeded would mean the protection had
been lost.

## How the image contract works

Worth understanding before changing `infrastructure/templates/user-data.yaml.tftpl`:

The image bakes `~/dotfiles` into `/home/ubuntu` and stashes a pristine copy at
`/opt/dev-vm/home-seed`, outside the mount point. The data volume then mounts
*over* `/home/ubuntu`, which would hide everything the image installed — so
`shared/bootstrap/seed-home.sh` restores the stash the first time it finds the
volume unseeded, marks it with `.dev-vm-seeded`, and leaves it alone on every later
boot. That is what makes the disk persistent rather than merely re-imaged.

Terraform's only job in that contract is writing `/etc/dev-vm/seed-home.env` with
`DATA_DISK_DEVICE`, because the device path is the one thing that differs per
cloud. Terraform always *requests* `/dev/sdf`; Nitro presents it to the guest as
`/dev/nvme1n1` and Xen as `/dev/xvdf`. Get that wrong and `seed-home.sh` fails
loudly on a device that is not there, which is the intended behaviour — silently
seeding the wrong disk would be worse.

See `shared/README.md`, "The home-seeding contract".
