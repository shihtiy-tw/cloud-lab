#!/usr/bin/env bash
#
# Mount the persistent data disk at the target user's home and seed it on first
# boot.
#
# Why this exists: the golden image bakes ~/dotfiles into /home/<user>, but the
# lifecycle design keeps /home/<user> on a separate disk that survives
# `terraform destroy`. Mounting that disk over the home directory would hide
# everything the image installed. So shared/bootstrap/install.sh stashes a
# pristine copy at ${HOME_SEED_DIR} (outside the mount point) and this script
# restores it the first time the volume is seen empty. On every later boot the
# volume already has content and is mounted untouched, which is what makes the
# disk persistent rather than merely re-imaged.
#
# Runs as root from dev-vm-seed-home.service, ordered before any login is
# possible. Idempotent: safe on every boot.
#
# Configuration is read from /etc/dev-vm/seed-home.env, which each cloud's
# Terraform writes via user_data / metadata / custom_data, because data disks
# surface under different device paths per cloud:
#
#   AWS    DATA_DISK_DEVICE=/dev/nvme1n1              (or /dev/xvdf on Xen)
#   GCP    DATA_DISK_DEVICE=/dev/disk/by-id/google-devhome
#   Azure  DATA_DISK_DEVICE=/dev/disk/azure/scsi1/lun0
#
# With no config, the first unmounted, unformatted disk is used. That fallback is
# a convenience for a single-data-disk VM, not a guarantee -- set the device
# explicitly when more than one data disk is attached.

set -euo pipefail

readonly CONFIG_FILE="/etc/dev-vm/seed-home.env"
readonly FS_LABEL_DEFAULT="devhome"

# shellcheck source=/dev/null
[[ -r ${CONFIG_FILE} ]] && . "${CONFIG_FILE}"

readonly TARGET_USER="${TARGET_USER:-ubuntu}"
readonly HOME_SEED_DIR="${HOME_SEED_DIR:-/opt/dev-vm/home-seed}"
readonly FS_LABEL="${FS_LABEL:-${FS_LABEL_DEFAULT}}"
readonly DATA_DISK_DEVICE="${DATA_DISK_DEVICE:-}"
readonly SEEDED_MARKER=".dev-vm-seeded"

log() { printf '[seed-home] %s\n' "$*" >&2; }
die() {
  printf '[seed-home] ERROR: %s\n' "$*" >&2
  exit 1
}

# resolve_device - the data disk to use, in preference order: the labelled
# filesystem (already seeded on a previous boot), the configured device, then the
# first candidate blank disk.
resolve_device() {
  local by_label="/dev/disk/by-label/${FS_LABEL}"
  if [[ -b ${by_label} ]]; then
    readlink -f "${by_label}"
    return 0
  fi

  if [[ -n ${DATA_DISK_DEVICE} ]]; then
    # A configured-but-absent device is a provisioning error worth failing
    # on, not something to silently work around.
    [[ -b ${DATA_DISK_DEVICE} ]] || die "configured DATA_DISK_DEVICE ${DATA_DISK_DEVICE} is not a block device"
    readlink -f "${DATA_DISK_DEVICE}"
    return 0
  fi

  find_blank_disk
}

# find_blank_disk - first whole disk with no filesystem, no partitions, and no
# mount. Excludes the root disk by checking for children.
find_blank_disk() {
  local name fstype mountpoint type
  while read -r name fstype mountpoint type; do
    [[ ${type} == "disk" ]] || continue
    [[ -z ${fstype} ]] || continue
    [[ -z ${mountpoint} ]] || continue
    # Skip anything with partitions; that is the OS disk.
    if [[ -n "$(lsblk -no NAME "/dev/${name}" | tail -n +2)" ]]; then
      continue
    fi
    printf '/dev/%s' "${name}"
    return 0
  done < <(lsblk -rno NAME,FSTYPE,MOUNTPOINT,TYPE)

  return 1
}

# wait_for_device - cloud data disks can attach after the network is up, so give
# the kernel a bounded window to notice.
wait_for_device() {
  local attempt device
  for attempt in $(seq 1 30); do
    if device="$(resolve_device)" && [[ -n ${device} ]]; then
      printf '%s' "${device}"
      return 0
    fi
    log "no data disk yet (attempt ${attempt}/30); waiting 2s"
    sleep 2
  done
  return 1
}

main() {
  [[ ${EUID} -eq 0 ]] || die "must run as root"

  local home_dir
  home_dir="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  [[ -n ${home_dir} ]] || die "cannot resolve home directory for ${TARGET_USER}"

  local device
  if ! device="$(wait_for_device)"; then
    # No data disk is a valid configuration -- the VM then simply runs on its
    # OS disk with the baked home. Do not fail the boot over it.
    log "no data disk found; using the image's home directory as-is"
    return 0
  fi
  log "using data disk ${device}"

  # Format only when there is no filesystem at all. Any existing filesystem is
  # someone's work; never reformat it.
  local existing_fstype
  existing_fstype="$(blkid -o value -s TYPE "${device}" 2> /dev/null || true)"
  if [[ -z ${existing_fstype} ]]; then
    log "no filesystem on ${device}; creating ext4 labelled ${FS_LABEL}"
    mkfs.ext4 -q -L "${FS_LABEL}" -m 0 "${device}"
  else
    log "keeping existing ${existing_fstype} filesystem on ${device}"
  fi

  local uuid
  uuid="$(blkid -o value -s UUID "${device}")"
  [[ -n ${uuid} ]] || die "cannot read UUID from ${device}"

  # Mount by UUID, never by device path: nvme/scsi enumeration order is not
  # stable across reboots and a wrong entry here is an unbootable VM.
  if ! grep -q "UUID=${uuid}" /etc/fstab; then
    log "adding ${home_dir} to /etc/fstab (UUID=${uuid})"
    printf 'UUID=%s %s ext4 defaults,nofail,x-systemd.growfs 0 2\n' \
      "${uuid}" "${home_dir}" >> /etc/fstab
    systemctl daemon-reload
  fi

  install -d "${home_dir}"
  if ! findmnt --target "${home_dir}" --source "UUID=${uuid}" > /dev/null 2>&1; then
    log "mounting ${device} at ${home_dir}"
    mount "${home_dir}"
  fi

  # An empty volume means first boot; anything else is existing work.
  if [[ -f "${home_dir}/${SEEDED_MARKER}" ]]; then
    log "home already seeded; leaving it alone"
  elif [[ -d ${HOME_SEED_DIR} ]]; then
    log "seeding ${home_dir} from ${HOME_SEED_DIR}"
    rsync -aHAX --numeric-ids "${HOME_SEED_DIR}/" "${home_dir}/"
    : > "${home_dir}/${SEEDED_MARKER}"
    chown "${TARGET_USER}:${TARGET_USER}" "${home_dir}/${SEEDED_MARKER}"
  else
    log "WARNING: ${HOME_SEED_DIR} missing; cannot seed ${home_dir}"
  fi

  # lost+found from mkfs leaves the mount root owned by root; the user must own
  # their home or zsh, ssh, and git all misbehave.
  chown "${TARGET_USER}:${TARGET_USER}" "${home_dir}"
  chmod 0750 "${home_dir}"

  log "done"
}

main "$@"
