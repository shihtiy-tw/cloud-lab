# Azure Compute - Dev VM

A personal Ubuntu development VM, built from the Compute Gallery image that
`shared/packer` publishes, with the dotfiles already installed and a home
directory that survives `terraform destroy`.

It has **no public IP** and **no inbound rule from the internet**. The only way
in is Azure Bastion, which is the cloud-native answer to "do not use ssh to open
to public network".

## The security properties

These are the deliverable. Each one is asserted by a unit test in `tests/unit/`,
so breaking one fails CI rather than a later review.

| Property | How |
|----------|-----|
| No public IP on the VM | `azurerm_network_interface.dev_vm.ip_configuration` has no `public_ip_address_id`. The only public IPs in the design belong to the NAT Gateway (outbound only) and, for Basic/Standard, to Bastion itself. |
| No internet-sourced inbound rule | The NSG's only Allow is TCP/22 from `VirtualNetwork`, and the variable that sets that scope rejects `Internet`, `*`, `0.0.0.0/0`, and `AzureCloud`. `DenyAllInbound` is stated explicitly at priority 4096. |
| No password | `disable_password_authentication = true`, and `admin_password` appears nowhere in the stack. |
| Disks encrypted | Platform-managed encryption at rest (unavoidable on managed disks) plus `encryption_at_host_enabled = true`. |
| Least-privilege identity | A user-assigned managed identity with **no** role assignments by default. `identity_role_assignments` validates that it is never Owner, Contributor, or User Access Administrator. Admin rights live on the human's Entra identity. |
| Home disk cannot be destroyed | `azurerm_managed_disk.home` carries `lifecycle { prevent_destroy = true }`. |

## Layout

| Path | Purpose |
|------|---------|
| `infrastructure/` | Terraform for the VM, disks, identity, Bastion, and RBAC. Calls `azure/shared/modules/network`. |
| `infrastructure/templates/` | The cloud-init document that configures the image's boot scripts. |
| `tests/unit/` | `init` + `validate` and source-level assertions on the properties above. No credentials needed. |
| `tests/integration/` | Applies for real, asserts the same properties against Azure, and runs the dotfiles' own tests on the box. |
| `utils/connect.sh` | Wrapper for connecting, starting/stopping, and the break-glass path. |

## Usage

```bash
cd infrastructure
cp terraform.tfvars.example terraform.tfvars   # then edit: ssh_public_keys is required
terraform init
terraform plan
terraform apply

terraform output -raw connection_instructions
```

Or through the repo's Makefile:

```bash
make plan      CLOUD=azure SERVICE=compute/dev-vm ENV=dev
make provision CLOUD=azure SERVICE=compute/dev-vm ENV=dev
make test      CLOUD=azure SERVICE=compute/dev-vm
make destroy   CLOUD=azure SERVICE=compute/dev-vm ENV=dev
```

## Connecting

`terraform output -raw connection_instructions` prints the exact commands for the
SKU you deployed. The VM auto-stops, so it is usually deallocated; start it first.

```bash
az vm start --name <vm> --resource-group <rg>

# Standard SKU only -- a real terminal:
az network bastion ssh \
  --name <bastion> \
  --resource-group <rg> \
  --target-resource-id <vm-id> \
  --auth-type AAD

# Any SKU -- the browser:
# Portal -> Virtual machines -> <vm> -> Connect -> Bastion
```

`utils/connect.sh` wraps all of that, including starting the VM:

```bash
./utils/connect.sh connect        # shell, or the portal path if the SKU is browser-only
./utils/connect.sh tunnel 2222    # forward 22 locally for scp / VS Code Remote-SSH
./utils/connect.sh status
./utils/connect.sh stop           # deallocate; billing for compute stops
./utils/connect.sh serial         # break-glass
```

### The Bastion SKU decision

This is the one real choice in the stack, and the provider is stricter than the
marketing pages suggest. Verified against **azurerm 5.1.0**, whose own validation
messages are quoted below.

| | Developer | Basic | Standard |
|---|---|---|---|
| Cost | Free | ~$0.19/hour (~$140/month) | ~$0.19/hour + scale units |
| `AzureBastionSubnet` | Not used | Required, /26 minimum | Required, /26 minimum |
| Public IP of yours | None | Standard, static | Standard, static |
| Terraform shape | `virtual_network_id`, no `ip_configuration` | `ip_configuration` with `public_ip_address_id` | same as Basic |
| Browser (portal) sessions | Yes | Yes | Yes |
| Native client (`az network bastion ssh`, scp, VS Code Remote-SSH) | **No** | **No** | **Yes** |
| Concurrency | One VM at a time | Dedicated instances | Scales out |
| Availability | Region-limited | All regions | All regions |

Two provider facts worth having in writing, because both contradict a reasonable
guess:

- **Developer SKU is expressible in Terraform.** The registry documentation
  describes `ip_configuration` as required, but the schema declares it as an
  optional list with `max_items = 1`, and the provider validates
  `` `virtual_network_id` is required when `sku` is `Developer` `` and
  `` `ip_configuration` with `public_ip_address_id` is required when `sku` is
  `Basic` or `Standard` ``. So no `az network bastion create --sku Developer`
  shim is needed here. If you are pinned to an older provider that cannot omit
  `ip_configuration`, set `create_bastion = false` and run
  `./utils/connect.sh create-developer-bastion`, which does exactly that call.
  Do not fake Developer SKU with a Basic-SKU resource -- that is a silent
  $140/month.
- **Basic SKU does not give you `az network bastion ssh`.** The provider rejects
  `tunneling_enabled` on anything below Standard:
  `` `tunneling_enabled` is only supported when `sku` is `Standard` or `Premium` ``.
  The same is true of `file_copy_enabled`, `ip_connect_enabled`, and
  `shareable_link_enabled`. Basic buys dedicated capacity, not a native client.
  **If you want a local terminal, `bastion_sku = "Standard"` is the only option.**

The default is `Developer`: free, and adequate for browser-based work. Switch to
`Standard` when the browser terminal starts costing you more than $140/month of
irritation, and set `create_bastion = false` if a Bastion already exists in the
VNet -- one serves every VM in it.

### Why Bastion needs no inbound rule from the internet

Bastion is out-of-band. The session terminates on Bastion's own instances, which
Azure reaches through its control plane, and Bastion then connects to the VM as
ordinary traffic inside the VNet. Nothing about that path requires the VM subnet
to accept a packet from the internet, which is why the only Allow rule in the NSG
is TCP/22 from `VirtualNetwork`.

## Integration with the shared image

The image (`shared/packer/dev-vm.pkr.hcl`) contains two boot scripts driven by env
files, and this stack's `custom_data` writes them:

| File | Contents |
|------|----------|
| `/etc/dev-vm/seed-home.env` | `TARGET_USER` (= `var.admin_username`), `HOME_SEED_DIR`, `FS_LABEL=devhome`, `DATA_DISK_DEVICE=/dev/disk/azure/scsi1/lun0` |
| `/etc/dev-vm/idle-shutdown.env` | `ENABLED`, `IDLE_MINUTES`, `CHECK_INTERVAL_MINUTES=5`, `LOAD_THRESHOLD`, `IGNORE_CONTAINERS` |

Three couplings that break silently if you touch one half:

1. **`lun = 0` and `/dev/disk/azure/scsi1/lun0`.** Azure exposes data disks at
   `lunN`. Change the attachment's `lun` without changing the device path and the
   VM boots fine while serving the image's copy of the home directory — which
   looks like "my files are gone", and any work done in that state is lost on the
   next reboot. `TestDataDiskLunMatchesSeedDevice` exists for this.
2. **`admin_username` and `TARGET_USER`.** The baked home seed belongs to the user
   the image was built for (`ubuntu`). A different admin username produces a VM
   whose dotfiles are installed for a user that does not exist.
3. **`CHECK_INTERVAL_MINUTES=5` and the timer on the image.**
   `dev-vm-idle-shutdown.timer` fires every 5 minutes and the script accumulates
   idle time in units of that interval, so disagreement makes `IDLE_MINUTES` mean
   something other than minutes.

`custom_data` is a real cloud-config document (`templates/cloud-init.yaml.tftpl`),
base64-encoded as `azurerm_linux_virtual_machine` requires. It installs nothing:
everything is already in the image.

One ordering caveat. `dev-vm-seed-home.service` runs `Before=sysinit.target`, and
so does `cloud-init-local.service`, so on first boot systemd may run seed-home
before cloud-init has written the env file. The cloud-config therefore re-runs the
unit from `runcmd` (safe: the script never reformats a disk that already has a
filesystem, and mounts by UUID). The deeper mitigation is `var.vm_size`: prefer a
size with **no local temporary disk** (Dsv5, not Ddsv5), so the script's
"first blank disk" fallback cannot pick a temp disk whose contents vanish on
deallocation.

## Cost

| Item | Running | Stopped (deallocated) |
|------|---------|----------------------|
| VM (`Standard_D2s_v5`, eastus) | ~$0.096/hour, ~$70/month if left on | $0 |
| OS disk (P10-ish, 30 GB Premium) | ~$5/month | ~$5/month |
| Home disk (128 GB Premium, P10) | ~$20/month | ~$20/month |
| **NAT Gateway** | **~$0.045/hour (~$32/month) + $0.045/GB processed** | **~$32/month — it keeps billing** |
| NAT public IP | ~$3.65/month | ~$3.65/month |
| Bastion Developer | Free | Free |
| Bastion Basic/Standard | ~$140/month + egress | ~$140/month |
| Boot diagnostics, auto-stop schedule, managed identity, NSG, VNet | Free | Free |

Prices are eastus list, rounded, and move; treat the ordering as the durable part.

**The NAT Gateway is the dominant standing cost once the VM auto-stops.** A
deallocated VM costs nothing for compute, so a stack that idles overnight is
paying ~$32/month for a gateway that is processing nothing, plus ~$25/month of
disk. That is the trade for having no public IP: Azure's implicit outbound access
is retired, so egress has to be bought.

If the VM is not going to be used for a while, `make destroy` is the right move.
It removes the VM, NIC, NAT Gateway, and public IP, and the home disk survives —
`prevent_destroy` makes Terraform refuse to delete it, and the next `apply`
re-attaches it with everything in place. Expect the destroy to report that it
cannot destroy the disk; that is the protection working. If you genuinely want the
disk gone, remove it from state and delete it deliberately:

```bash
terraform state rm azurerm_managed_disk.home
az disk delete --name <project>-dev-vm-<env>-home --resource-group <rg> --yes
```

Two layers of auto-stop keep the VM from being the cost driver:
`azurerm_dev_test_global_vm_shutdown_schedule` is the clock-based backstop (it
works on any ordinary VM, not just DevTest Labs VMs — that is the cheap trick
here), and the on-box idle timer from the image reacts to actual idleness.

## Recovery

There is no SSH from the internet, so a broken Bastion is a lockout unless the
break-glass path is already in place. It is: boot diagnostics are enabled with the
platform-managed storage account, which is what the serial console needs.

1. **Is it running?**
   `az vm get-instance-view --name <vm> --resource-group <rg> --query "instanceView.statuses"`.
   The auto-stop or the idle timer has probably deallocated it. `az vm start`.
2. **Boot log.**
   `az vm boot-diagnostics get-boot-log --name <vm> --resource-group <rg>`, or
   `./utils/connect.sh serial`. This shows cloud-init and
   `dev-vm-seed-home.service` output — the usual cause of a VM that boots but
   behaves oddly is a home disk that did not mount.
3. **Serial console.** Portal → the VM → Help → Serial console. This is a
   direct connection to the VM's serial port through the Azure control plane: it
   does not use the NIC, the NSG, the NAT Gateway, or Bastion, so it works when
   every network path is broken. You need `Virtual Machine Contributor` on the VM
   and boot diagnostics enabled — both already configured.
4. **Run a command without any session.**
   `az vm run-command invoke --command-id RunShellScript --name <vm> --resource-group <rg> --scripts "systemctl status dev-vm-seed-home"`.
   Same brokered path the integration tests use; no network reachability needed.
5. **Give up on the VM, keep the work.** `terraform destroy` (the home disk
   refuses to be destroyed), then `terraform apply` for a fresh VM with the same
   home. This is the routine repair, not a last resort — the design exists to make
   the VM disposable.

## Day one of CSP access

The order matters; several of these fail an `apply` half-way through if skipped.

1. **Subscription and login.**

   ```bash
   az login
   az account set --subscription <subscription-id>
   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   ```

2. **Register the resource providers** the stack touches. New subscriptions have
   most but rarely all of these:

   ```bash
   for ns in Microsoft.Compute Microsoft.Network Microsoft.Storage \
             Microsoft.ManagedIdentity Microsoft.DevTestLab; do
     az provider register --namespace "$ns"
   done
   ```

   `Microsoft.DevTestLab` is the surprise: it is what the auto-stop schedule uses.
3. **Register the EncryptionAtHost feature.** One-off per subscription, and the
   most common day-one apply failure here:

   ```bash
   az feature register --namespace Microsoft.Compute --name EncryptionAtHost
   az feature show --namespace Microsoft.Compute --name EncryptionAtHost \
     --query properties.state    # wait for "Registered", can take minutes
   az provider register --namespace Microsoft.Compute
   ```

   Or set `encryption_at_host_enabled = false` and come back to it.
4. **Check quota** for the VM family in your region. A fresh subscription often
   has 0 vCPU quota for some families:
   `az vm list-usage --location eastus --query "[?contains(name.value, 'standardDSv5Family')]"`.
5. **Check Bastion Developer availability** in your region if you are using that
   SKU; it is not available everywhere. `az network bastion create --help` lists
   nothing useful here — check the Bastion documentation, or deploy `Standard`.
6. **Build the image** before the first apply, or the gallery lookup has nothing
   to find:

   ```bash
   cd shared/packer && packer init . \
     && packer build -only='dev-vm.azure-arm.dev-vm' -var-file=azure.pkrvars.hcl .
   ```

   Then set `image_version` to what you published (or `image_id` to the exact id).
7. **Your own object id**, for `developer_principal_ids` — without it nobody has
   the role assignments Bastion needs:
   `az ad signed-in-user show --query id -o tsv`.
8. **Your own permissions.** Creating role assignments requires `Owner` or `User
   Access Administrator` on the scope. With only `Contributor`, everything else in
   this stack applies and the `azurerm_role_assignment` resources fail — set
   `developer_principal_ids = []` and have an admin grant the roles.
9. **An SSH key.** `ssh-keygen -t ed25519` if you have none; put the public key in
   `ssh_public_keys`. The stack fails at plan time with an explanation if it is
   empty, because password auth is disabled.

## Validate without credentials

Everything here validates with no Azure account at all:

```bash
terraform -chdir=infrastructure init -backend=false -input=false
terraform -chdir=infrastructure validate
terraform -chdir=../../shared/modules/network init -backend=false -input=false
terraform -chdir=../../shared/modules/network validate
terraform fmt -check -recursive ../..

cd tests && go test -short -v ./unit/...
```

The integration tests need a sandbox subscription; `-short` skips them.

## Inputs and outputs

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
