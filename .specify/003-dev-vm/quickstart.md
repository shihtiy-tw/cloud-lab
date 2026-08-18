# Quickstart: Multi-Cloud Development VM

## 1. Prerequisites

- `terraform` >= 1.5, `packer` >= 1.9
- The cloud CLI for the cloud you are using: `aws`, `gcloud`, or `az`
- For AWS: the `session-manager-plugin` (the dotfiles' `make aws` installs it)
- Credentials for the target cloud

## 2. Build the image

One template, three sources. Build only the cloud you need:

```bash
packer init shared/packer/

packer build -only='dev-vm.amazon-ebs.dev-vm' \
  -var aws_subnet_id=subnet-xxxx shared/packer/

packer build -only='dev-vm.googlecompute.dev-vm' \
  -var gcp_project_id=my-project -var gcp_subnetwork=my-subnet shared/packer/

packer build -only='dev-vm.azure-arm.dev-vm' \
  -var azure_subscription_id=xxxx \
  -var azure_build_allowed_cidr="$(curl -s ifconfig.me)/32" shared/packer/
```

The build takes 30-45 minutes: neovim's mason LSP servers and the Kubernetes
toolchain are not fast. `shared/packer/manifest.json` records the resulting image
id to feed to Terraform.

Pin `dotfiles_ref` to a commit SHA for a reproducible image; the default
`develop` is a moving target.

## 3. Provision

```bash
./scripts/cloud.provision.sh --cloud aws   --service compute/dev-vm --env dev
./scripts/cloud.provision.sh --cloud gcp   --service compute/dev-vm --env dev
./scripts/cloud.provision.sh --cloud azure --service compute/dev-vm --env dev
```

## 4. Connect

No cloud exposes SSH to the internet, so each has its own path:

```bash
# AWS -- Session Manager, no ingress rule exists at all
aws ssm start-session --target "$INSTANCE_ID"

# GCP -- IAP tunnel; the only :22 ingress is from 35.235.240.0/20
gcloud compute ssh dev-vm --tunnel-through-iap --zone us-central1-a

# Azure -- Bastion. Developer (the default) is browser-only:
#   portal -> VM -> Connect -> Bastion
# The native client needs the STANDARD SKU -- not Basic. The provider rejects
# tunneling_enabled below Standard, so Basic costs ~$140/mo and is still
# browser-only. azure/compute/dev-vm/utils/connect.sh refuses to pretend.
az network bastion ssh --name <bastion> --resource-group <rg> \
  --target-resource-id "$VM_ID" --auth-type AAD
```

## 5. Verify on the box

Reuse the dotfiles' own test targets rather than inventing checks:

```bash
cd ~/dotfiles && make test-install && make test-symlinks
echo "$SHELL"                  # /usr/bin/zsh
kubectl version --client && helm version
cat /etc/dev-vm-build.json     # dotfiles SHA, ubuntu release, build time
```

## 6. Day-one-of-CSP-access checklist

The whole design is currently verified statically only. On first real access, run
this in order — it is the list of things static verification cannot prove:

```bash
# 1. The VM must have no public address
aws ec2 describe-instances --instance-ids "$ID" \
  --query 'Reservations[].Instances[].PublicIpAddress'          # must be null
gcloud compute instances describe dev-vm \
  --format='value(networkInterfaces[0].accessConfigs)'          # must be empty
az vm list-ip-addresses --name dev-vm \
  --query '[].virtualMachine.network.publicIpAddresses'         # must be []

# 2. Connect the intended way (section 4)

# 3. The dotfiles actually installed (section 5)

# 4. The persistent home survives a destroy.
#    NOTE: a plain destroy REFUSES to run. prevent_destroy on the data disk
#    aborts the whole operation, not just that one resource -- that is Terraform
#    behaving correctly, and it is why the recipe below is targeted. Each
#    service README carries the exact target list for its cloud.
terraform -chdir=aws/compute/dev-vm/infrastructure destroy \
  -target=aws_instance.dev_vm -target=aws_nat_gateway.this
./scripts/cloud.provision.sh --cloud aws --service compute/dev-vm --env dev
# reconnect: ~/dotfiles and any work must still be there

# 5. Auto-stop fires
#    leave the box idle past IDLE_MINUTES; it should power off on its own
journalctl -u dev-vm-idle-shutdown

# 6. Break-glass works BEFORE you need it
#    AWS:   aws ec2-instance-connect send-serial-console-ssh-public-key ...
#    GCP:   gcloud compute instances add-metadata dev-vm --metadata serial-port-enable=TRUE
#    Azure: az serial-console connect --name dev-vm --resource-group <rg>

# 7. Cost is what you think it is
./scripts/cloud.cost.sh --cloud aws --service compute/dev-vm
```

## 7. Cost note

The VMs auto-stop, so the standing cost is the **NAT**, not the compute: roughly
$32/mo per cloud, ~$96/mo with all three left up. Tear the stack down when a
cloud is idle — the data disk is `prevent_destroy`, so work survives.

Because `prevent_destroy` aborts a whole `terraform destroy`, tearing down means a
targeted destroy of the VM and the NAT (which is where the money is). Each
service README documents the target list for its cloud, along with the explicit
data-losing path for when you really do want the disk gone.
