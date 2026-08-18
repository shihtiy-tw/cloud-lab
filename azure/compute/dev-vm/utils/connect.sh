#!/usr/bin/env bash
#
# Open a session on the Azure dev VM, or operate the access path around it.
#
# Everything here is a convenience wrapper over `az` and `terraform output`. It
# exists because the connection command is long, differs by Bastion SKU, and is
# the one command you need on the day Bastion is misbehaving -- which is the worst
# day to be reconstructing it from documentation.
#
# There is no SSH-from-the-internet path to fall back on: the VM has no public IP
# and the NSG allows nothing inbound from the internet. That is deliberate. If
# Bastion is broken, use `serial` below.
#
# Usage:
#   connect.sh connect                 # shell on the VM (Standard SKU) or portal URL
#   connect.sh tunnel [local-port]     # forward 22 to a local port for scp/VS Code
#   connect.sh start | stop | status    # the VM auto-stops; this starts it again
#   connect.sh serial                  # break-glass: boot log and serial console
#   connect.sh create-developer-bastion # provider-independent Developer-SKU fallback
#
# Requires: az CLI (logged in), terraform. Reads outputs from ../infrastructure.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly TF_DIR="${TF_DIR:-${SCRIPT_DIR}/../infrastructure}"

log() { printf '[dev-vm] %s\n' "$*" >&2; }
die() {
  printf '[dev-vm] ERROR: %s\n' "$*" >&2
  exit 1
}

require() {
  command -v "$1" > /dev/null 2>&1 || die "$1 is required but not installed"
}

# tf_output <name> - a single Terraform output, or empty if it is absent. Empty
# rather than fatal so `status` can still report on a half-applied stack.
tf_output() {
  terraform -chdir="${TF_DIR}" output -raw "$1" 2> /dev/null || true
}

# load_stack - resolve everything the az commands need, once.
load_stack() {
  VM_NAME="$(tf_output vm_name)"
  VM_ID="$(tf_output vm_id)"
  RESOURCE_GROUP="$(tf_output resource_group_name)"
  BASTION_NAME="$(tf_output bastion_host_name)"
  BASTION_SKU="$(tf_output bastion_sku)"
  ADMIN_USER="$(tf_output admin_username)"

  [[ -n ${VM_NAME} ]] || die "no vm_name output in ${TF_DIR}; has this stack been applied?"
}

# ensure_running - Bastion cannot reach a deallocated VM, and the auto-stop means
# it usually is one. Starting it is idempotent and takes about 30 seconds.
ensure_running() {
  local state
  state="$(az vm get-instance-view \
    --name "${VM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]" \
    --output tsv)"

  if [[ ${state} != "PowerState/running" ]]; then
    log "VM is ${state:-unknown}; starting it"
    az vm start --name "${VM_NAME}" --resource-group "${RESOURCE_GROUP}" --output none
  fi
}

# auth_args - AAD when the AADSSHLoginForLinux extension is installed, otherwise
# the SSH key. AAD is preferred: access follows the role assignment, so revoking
# someone does not mean rotating a key on the box.
auth_args() {
  local extensions
  extensions="$(az vm extension list \
    --vm-name "${VM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[].name" --output tsv 2> /dev/null || true)"

  if grep -q "AADSSHLoginForLinux" <<< "${extensions}"; then
    printf '%s' "--auth-type AAD"
  else
    printf '%s' "--auth-type ssh-key --username ${ADMIN_USER} --ssh-key ${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
  fi
}

cmd_connect() {
  load_stack

  # Native-client tunneling is Standard SKU and above; Developer and Basic are
  # browser-only, and the azurerm provider enforces that too.
  if [[ ${BASTION_SKU} != "Standard" ]]; then
    log "Bastion SKU is ${BASTION_SKU:-none}, which has no native-client support."
    log "Connect from the portal:"
    log "  Virtual machines -> ${VM_NAME} -> Connect -> Bastion"
    log "Set bastion_sku = \"Standard\" if you want a local terminal."
    return 0
  fi

  ensure_running

  local auth
  auth="$(auth_args)"
  log "opening a Bastion session to ${VM_NAME}"
  # shellcheck disable=SC2086 # auth intentionally expands to several arguments
  az network bastion ssh \
    --name "${BASTION_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --target-resource-id "${VM_ID}" \
    ${auth}
}

cmd_tunnel() {
  local local_port="${1:-2222}"
  load_stack

  [[ ${BASTION_SKU} == "Standard" ]] || die "tunneling needs the Standard Bastion SKU; ${BASTION_SKU:-none} is browser-only"
  ensure_running

  log "forwarding ${VM_NAME}:22 to 127.0.0.1:${local_port} (Ctrl-C to stop)"
  log "then: ssh ${ADMIN_USER}@127.0.0.1 -p ${local_port}"
  az network bastion tunnel \
    --name "${BASTION_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --target-resource-id "${VM_ID}" \
    --resource-port 22 \
    --port "${local_port}"
}

cmd_start() {
  load_stack
  az vm start --name "${VM_NAME}" --resource-group "${RESOURCE_GROUP}" --output none
  log "${VM_NAME} started"
}

# Deallocate, not just power off: a stopped-but-allocated VM still bills for
# compute. The on-box idle timer uses `systemctl poweroff`, which Azure treats as
# a deallocation, so this matches what the VM does to itself.
cmd_stop() {
  load_stack
  az vm deallocate --name "${VM_NAME}" --resource-group "${RESOURCE_GROUP}" --output none
  log "${VM_NAME} deallocated; the home disk is untouched"
}

cmd_status() {
  load_stack
  printf 'VM:             %s\n' "${VM_NAME}"
  printf 'Resource group: %s\n' "${RESOURCE_GROUP}"
  printf 'Bastion:        %s (%s)\n' "${BASTION_NAME:-none}" "${BASTION_SKU:-none}"
  az vm get-instance-view \
    --name "${VM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "{power: instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus | [0], size: hardwareProfile.vmSize, publicIps: length(networkProfile.networkInterfaces)}" \
    --output yaml
}

# Break-glass. If Bastion is down, misconfigured, or the guest's sshd is broken,
# the serial console is the only way in -- and it does not depend on the network
# stack, the NSG, or Bastion at all. Boot diagnostics are enabled on the VM
# precisely so this works on the day it is needed.
cmd_serial() {
  load_stack
  log "last boot log for ${VM_NAME}:"
  az vm boot-diagnostics get-boot-log \
    --name "${VM_NAME}" \
    --resource-group "${RESOURCE_GROUP}" || log "no boot log yet"

  log "for an interactive root prompt:"
  log "  Portal -> Virtual machines -> ${VM_NAME} -> Help -> Serial console"
  log "  (needs 'Virtual Machine Contributor' and boot diagnostics, both already configured)"
}

# Fallback path for anyone pinned to a provider that cannot express the Developer
# SKU. azurerm 5.1 can -- `virtual_network_id` plus no `ip_configuration` -- so
# this is not used by the Terraform in this directory. It is here because the
# alternative, faking Developer SKU with a Basic-SKU resource, would silently
# create a ~$140/month bill.
cmd_create_developer_bastion() {
  load_stack
  local vnet_name
  vnet_name="$(terraform -chdir="${TF_DIR}" output -json network 2> /dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["vnet_id"].rsplit("/", 1)[-1])')"
  [[ -n ${vnet_name} ]] || die "cannot resolve the VNet name from Terraform outputs"

  log "creating a Developer-SKU Bastion on ${vnet_name} (free, browser-only, one VM at a time)"
  az network bastion create \
    --name "${VM_NAME}-bastion" \
    --resource-group "${RESOURCE_GROUP}" \
    --vnet-name "${vnet_name}" \
    --sku Developer \
    --output none
  log "created. Set create_bastion = false in tfvars so Terraform does not fight it."
}

main() {
  require az
  require terraform

  local command="${1:-connect}"
  shift || true

  case "${command}" in
    connect) cmd_connect "$@" ;;
    tunnel) cmd_tunnel "$@" ;;
    start) cmd_start ;;
    stop) cmd_stop ;;
    status) cmd_status ;;
    serial) cmd_serial ;;
    create-developer-bastion) cmd_create_developer_bastion ;;
    -h | --help | help) sed -n '2,25p' "${BASH_SOURCE[0]}" ;;
    *) die "unknown command: ${command} (try --help)" ;;
  esac
}

main "$@"
