# Runbook: dev-vm lockout recovery (break-glass)

**Applies to** `{aws,gcp,azure}/compute/dev-vm`
**Read this before you need it.** Most of the preparation must happen while you
still have access.

---

## Why this runbook exists

The dev VM has no SSH port reachable from the internet. That is the point — but it
means the brokered path *is* the only path, and a broken broker is a total
lockout:

| Cloud | What breaks access |
|-------|--------------------|
| AWS | `amazon-ssm-agent` stops, dies, or loses its IAM permissions; no NAT egress to reach the SSM endpoints |
| GCP | IAP firewall rule deleted, `roles/iap.tunnelResourceAccessor` revoked, OS Login misconfigured, guest agent dead |
| Azure | Bastion deleted or region-unavailable, NSG changed, `waagent` deprovisioned or dead |

The single most common cause is not the broker at all: **losing egress**. All
three agents phone *out* to their control plane. Delete the NAT Gateway to save
$32/mo and the VM goes dark while looking perfectly healthy in the console.

---

## The recovery ladder

Work down it. Each tier makes fewer assumptions than the one above.

| Tier | Mechanism | Requires | Gets you |
|------|-----------|----------|----------|
| 0 | Control-plane command execution | the guest agent alive | run commands, no interactive shell |
| 1 | Serial console | the kernel booting | interactive console, **needs a local password** |
| 2 | Rescue disk | the disk intact | offline filesystem access |
| 3 | Rebuild | the data disk intact | a fresh VM, work preserved |

Tier 3 is cheap by design — `/home/ubuntu` is on a `prevent_destroy` disk — so do
not spend an hour on Tier 1 for a box you can replace in ten minutes.

---

## Tier 0 — control-plane command execution

Works when the *interactive* broker is broken but the guest agent still talks to
the control plane. Try this first; it is the least invasive.

```bash
# AWS -- only helps if the SSM agent is alive, i.e. not for agent failures.
# Check first:
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$ID" \
  --query 'InstanceInformationList[].[PingStatus,LastPingDateTime,AgentVersion]'
aws ssm send-command --instance-ids "$ID" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["systemctl status amazon-ssm-agent","ip route","journalctl -u dev-vm-seed-home --no-pager"]'
aws ssm get-command-invocation --command-id "$CMD" --instance-id "$ID"

# Azure -- run-command goes through waagent on the control plane, NOT through
# Bastion. So it survives a deleted Bastion entirely. This is Azure's best
# break-glass channel.
az vm run-command invoke --name dev-vm --resource-group "$RG" \
  --command-id RunShellScript \
  --scripts "systemctl status walinuxagent; ip route; systemctl status dev-vm-seed-home"

# GCP -- no run-command equivalent. Use the startup-script trick in Tier 1.5.
```

**Gotcha:** on AWS, if the SSM *agent* is what broke, `send-command` is exactly as
dead as `start-session`. Check `PingStatus` before assuming.

---

## Tier 1 — serial console

### The gotcha that makes this useless if you skip it

All three serial consoles drop you at a **login prompt**, and the dev VM is built
with `disable_password_authentication = true` / SSH-keys-only. There is no
password to type. An unprepared serial console gives you boot logs and nothing
more.

Pick one before you need it:

1. **Accept read-only.** Use the serial console for boot output only, and rely on
   Tier 2/3 to fix anything. Reasonable for a lab; this is the current default.
2. **Set a break-glass password.** Store it in Secrets Manager / Secret Manager /
   Key Vault and have cloud-init set it for a dedicated `breakglass` user. This
   re-introduces a password on the box — a real tradeoff, and the reason it is not
   the default.
3. **Azure only:** reset credentials on demand via the VMAccess extension, which
   needs no prior preparation:

   ```bash
   az vm user update --name dev-vm --resource-group "$RG" \
     --username breakglass --password "$(openssl rand -base64 24)"
   ```

   This is the only cloud of the three that can mint console credentials after the
   lockout has already happened. Note it enables password auth for that user.

### AWS — EC2 Serial Console

```bash
# One-time, per region, at the ACCOUNT level. Do this now, not during an outage.
aws ec2 enable-serial-console-access
aws ec2 get-serial-console-access-status

# During an incident
ssh-keygen -t ed25519 -f /tmp/serial -N ''
aws ec2-instance-connect send-serial-console-ssh-public-key \
  --instance-id "$ID" --serial-port 0 --ssh-public-key file:///tmp/serial.pub
ssh -i /tmp/serial "$ID.port0@serial-console.ec2-instance-connect.$REGION.aws"
```

Constraints: **Nitro instances only** (any modern `t3`/`m6i`/`c7g`; not `t2`), not
available in every region, one session per instance at a time, and the pushed key
expires after 60 seconds — connect immediately.

### GCP — serial port

```bash
gcloud compute instances add-metadata dev-vm --zone "$ZONE" \
  --metadata serial-port-enable=TRUE
gcloud compute connect-to-serial-port dev-vm --zone "$ZONE"

# Read-only boot output needs no metadata change and is often enough:
gcloud compute instances get-serial-port-output dev-vm --zone "$ZONE"
```

Constraint: the `compute.disableSerialPortAccess` org policy blocks this
outright. Check it before relying on it. It is off by default in the VM's
Terraform on purpose — an always-open serial port is an extra attack surface, and
this runbook is the compensating control.

### GCP Tier 1.5 — the startup-script trick

GCP re-runs `startup-script` metadata on **every boot**, unlike AWS user_data.
That makes it a genuine repair channel with no shell at all:

```bash
gcloud compute instances add-metadata dev-vm --zone "$ZONE" \
  --metadata startup-script='#!/bin/bash
    systemctl restart google-guest-agent
    # re-add the IAP firewall path, fix sshd, whatever broke
  '
gcloud compute instances reset dev-vm --zone "$ZONE"
# Then REMOVE it -- a lingering repair script is a surprise on the next boot.
gcloud compute instances remove-metadata dev-vm --zone "$ZONE" --keys startup-script
```

### Azure — serial console

```bash
az serial-console connect --name dev-vm --resource-group "$RG"
```

Requires boot diagnostics enabled with a storage account (the VM's Terraform
enables it) and the *Virtual Machine Contributor* role.

---

## Tier 2 — rescue disk

When the kernel will not boot (bad `/etc/fstab`, full disk, broken initramfs).
`seed-home.sh` writes fstab entries with `nofail`, which is specifically to stop a
missing data disk from wedging the boot — but a corrupted root disk can still do
it.

The shape is identical in all three clouds: stop the VM, detach its OS disk,
attach it as a data disk to a second VM, mount, fix, reverse.

```bash
# AWS
aws ec2 stop-instances --instance-ids "$ID"
aws ec2 detach-volume --volume-id "$ROOT_VOL"
aws ec2 attach-volume --volume-id "$ROOT_VOL" --instance-id "$RESCUE_ID" --device /dev/sdf
# on the rescue box: mkdir /mnt/r && mount /dev/nvme1n1p1 /mnt/r && $EDITOR /mnt/r/etc/fstab

# GCP
gcloud compute instances stop dev-vm --zone "$ZONE"
gcloud compute instances detach-disk dev-vm --disk dev-vm-boot --zone "$ZONE"
gcloud compute instances attach-disk rescue --disk dev-vm-boot --zone "$ZONE"

# Azure -- has a purpose-built command for this
az vm repair create --name dev-vm --resource-group "$RG" --verbose
az vm repair run   --name dev-vm --resource-group "$RG" --run-id linux-alar2
az vm repair restore --name dev-vm --resource-group "$RG"
```

**Do not detach the data disk to inspect it.** It carries `prevent_destroy` and
holds the only copy of your work; a detach/attach cycle is an unnecessary risk
when the rebuild path preserves it automatically.

---

## Tier 3 — rebuild (usually the right answer)

The design makes this the cheap option deliberately. The VM is disposable; the
data disk is not.

```bash
cd "$CLOUD/compute/dev-vm"
terraform destroy   # the data disk refuses to be destroyed -- that is correct
terraform apply     # new VM, same disk, re-attached and re-mounted
```

On the new box, `seed-home.sh` finds `/home/ubuntu/.dev-vm-seeded` already
present, mounts the disk untouched, and skips seeding. Your work is there.

If `terraform destroy` fails with "Instance cannot be destroyed" on the data
disk, that is the `prevent_destroy` guard doing its job. Target the VM instead:

```bash
terraform destroy -target=<vm_resource_address>
```

---

## Preparation checklist

Do these while you still have access. Each one is a tier of the ladder that will
not work otherwise.

- [ ] AWS: `aws ec2 enable-serial-console-access` in every region you use
- [ ] AWS: confirm the instance type is Nitro-based
- [ ] GCP: confirm `compute.disableSerialPortAccess` is not enforced on the org
- [ ] Azure: boot diagnostics enabled (Terraform does this) and you hold *Virtual
      Machine Contributor*
- [ ] Decide the password question in Tier 1 and record the decision
- [ ] Rehearse Tier 3 once — destroy and re-apply, and confirm `/home/ubuntu`
      survived. This is item 4 of the day-one checklist in
      [`.specify/003-dev-vm/quickstart.md`](../../.specify/003-dev-vm/quickstart.md)
- [ ] Do not delete the NAT to save money without expecting the VM to go dark

---

## Diagnosis first

Before climbing the ladder, rule out the boring causes. In order of how often
they are the answer:

1. **Egress gone.** NAT Gateway / Cloud NAT / NAT Gateway deleted, or its route
   removed. The agent cannot reach its control plane. Check the route table.
2. **IAM changed.** The instance profile, service account, or managed identity
   lost the permission the agent needs to register.
3. **Your own permissions.** `ssm:StartSession`,
   `roles/iap.tunnelResourceAccessor`, or *Virtual Machine User Login* revoked.
   Read the error text — brokered access failures usually say so plainly.
4. **The VM is stopped.** Auto-stop worked exactly as designed. Start it.
   `journalctl -u dev-vm-idle-shutdown` explains why, once you are back in.
5. **Firewall drift.** GCP especially: if the `35.235.240.0/20` rule was deleted,
   re-creating it is a one-line `terraform apply`.

---

## Status of this runbook

Written alongside the initial implementation, with **no CSP credentials
available** — so every command here is from documentation and none has been
executed against a live account. Treat the exact flag spellings as unverified
until the preparation checklist has been walked through for real. The tier
structure and the password gotcha are the parts worth trusting; the CLI syntax is
the part to double-check.
