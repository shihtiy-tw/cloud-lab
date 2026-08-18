#!/usr/bin/env bash
#
# Bake the shihtiy-tw/dotfiles development environment into a machine image.
#
# This is the single provisioner shared by all three Packer sources
# (amazon-ebs, googlecompute, azure-arm) in shared/packer/dev-vm.pkr.hcl. It is
# deliberately cloud-agnostic: no cloud CLI is called and no metadata service is
# read. Everything cloud-specific lives in the Terraform stacks under
# <cloud>/compute/dev-vm/.
#
# Runs as root during a Packer build. The dotfiles steps are executed as
# TARGET_USER because upstream `make init` symlinks into $HOME and resolves
# every config path from ~/dotfiles.
#
# Why a golden image instead of cloud-init at boot: upstream `make install` is
# unattended and invasive (it purges the distro Docker packages and installs
# Docker CE). Running that once at build time is fine; running it on every boot
# would be slow and would make each boot a fresh opportunity to fail.
#
# Environment (all optional, defaults shown):
#   TARGET_USER=ubuntu             user that owns the environment
#   DOTFILES_REPO=https://github.com/shihtiy-tw/dotfiles.git
#   DOTFILES_REF=develop           branch, tag, or -- preferably -- a commit SHA
#   DOTFILES_EXTRAS="cloud"        space-separated extra make targets
#   HOME_SEED_DIR=/opt/dev-vm/home-seed
#
# Usage:
#   sudo -E ./install.sh

set -euo pipefail

readonly TARGET_USER="${TARGET_USER:-ubuntu}"
readonly DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/shihtiy-tw/dotfiles.git}"
readonly DOTFILES_REF="${DOTFILES_REF:-develop}"
readonly DOTFILES_EXTRAS="${DOTFILES_EXTRAS:-cloud}"
readonly HOME_SEED_DIR="${HOME_SEED_DIR:-/opt/dev-vm/home-seed}"
readonly BUILD_STAMP="/etc/dev-vm-build.json"

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

log() { printf '[install] %s\n' "$*" >&2; }
die() {
  printf '[install] ERROR: %s\n' "$*" >&2
  exit 1
}

# run_as <user> <command...> - run a command as the target user with a real
# login environment, so ~/.profile-derived PATH entries and $HOME are correct.
run_as() {
  local user="$1"
  shift
  sudo -H -u "${user}" -- "$@"
}

# apt_retry <args...> - apt-get with retries. Cloud images frequently race
# unattended-upgrades on first boot, which holds the dpkg lock.
apt_retry() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if apt-get "$@"; then
      return 0
    fi
    log "apt-get $1 failed (attempt ${attempt}/5); retrying in 15s"
    sleep 15
  done
  die "apt-get $1 failed after 5 attempts"
}

# has_make_target <dir> <target> - true when the Makefile really defines the
# target. Upstream is a moving repo; probing beats assuming, and it turns a
# renamed target into a clear warning instead of a mid-build failure.
has_make_target() {
  local dir="$1" target="$2"
  run_as "${TARGET_USER}" make -C "${dir}" -n "${target}" > /dev/null 2>&1
}

# make_target <dir> <target> - run a make target, skipping with a warning when
# upstream does not define it.
make_target() {
  local dir="$1" target="$2"
  if ! has_make_target "${dir}" "${target}"; then
    log "WARNING: dotfiles Makefile has no '${target}' target; skipping"
    return 0
  fi
  log "running: make ${target}"
  run_as "${TARGET_USER}" make -C "${dir}" "${target}"
}

main() {
  [[ ${EUID} -eq 0 ]] || die "must run as root (use sudo -E)"
  id -u "${TARGET_USER}" > /dev/null 2>&1 || die "user ${TARGET_USER} does not exist"

  local home_dir
  home_dir="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  [[ -n ${home_dir} ]] || die "cannot resolve home directory for ${TARGET_USER}"

  # Upstream `make install` needs to escalate. Cloud Ubuntu images give the
  # default user passwordless sudo already; assert it rather than discover it
  # halfway through a 10-minute install.
  run_as "${TARGET_USER}" sudo -n true 2> /dev/null \
    || die "${TARGET_USER} lacks passwordless sudo, which 'make install' requires"

  log "waiting for cloud-init to finish so it cannot race our apt usage"
  cloud-init status --wait > /dev/null 2>&1 || log "cloud-init not present or already done"

  log "installing bootstrap prerequisites"
  apt_retry update -y
  apt_retry install -y --no-install-recommends \
    ca-certificates curl git make rsync sudo zsh

  # The path is not incidental: dotfiles' make/init.sh resolves every config
  # from ~/dotfiles, so cloning anywhere else silently produces broken
  # symlinks.
  local dotfiles_dir="${home_dir}/dotfiles"

  if [[ -d "${dotfiles_dir}/.git" ]]; then
    log "dotfiles already present; fetching ${DOTFILES_REF}"
    run_as "${TARGET_USER}" git -C "${dotfiles_dir}" remote set-url origin "${DOTFILES_REPO}"
    run_as "${TARGET_USER}" git -C "${dotfiles_dir}" fetch --tags --prune origin
  else
    log "cloning ${DOTFILES_REPO} into ${dotfiles_dir}"
    run_as "${TARGET_USER}" git clone "${DOTFILES_REPO}" "${dotfiles_dir}"
  fi

  # Detached checkout, so the recorded SHA is exactly what is on the image
  # even when DOTFILES_REF is a moving branch like develop.
  log "checking out ${DOTFILES_REF}"
  run_as "${TARGET_USER}" git -C "${dotfiles_dir}" -c advice.detachedHead=false \
    checkout --force "${DOTFILES_REF}"
  run_as "${TARGET_USER}" git -C "${dotfiles_dir}" submodule update --init --recursive

  local dotfiles_sha
  dotfiles_sha="$(run_as "${TARGET_USER}" git -C "${dotfiles_dir}" rev-parse HEAD)"
  log "dotfiles pinned at ${dotfiles_sha}"

  # Order matters: install lays down the tools, init symlinks the configs that
  # reference them, extras add the cloud and kubernetes toolchains.
  make_target "${dotfiles_dir}" install
  make_target "${dotfiles_dir}" init

  local target
  for target in ${DOTFILES_EXTRAS}; do
    make_target "${dotfiles_dir}" "${target}"
  done

  local zsh_path
  zsh_path="$(command -v zsh || true)"
  if [[ -n ${zsh_path} ]]; then
    log "setting ${TARGET_USER} login shell to ${zsh_path}"
    chsh -s "${zsh_path}" "${TARGET_USER}"
  else
    log "WARNING: zsh not found after install; leaving login shell unchanged"
  fi

  # A persistent data disk gets mounted over ${home_dir} at first boot, which
  # would hide everything installed above. Keep a pristine copy outside the
  # mount point; shared/bootstrap/seed-home.sh restores it into the empty
  # volume. See that script for the other half of this contract.
  log "seeding ${HOME_SEED_DIR} from ${home_dir}"
  install -d -m 0755 "$(dirname "${HOME_SEED_DIR}")"
  rm -rf "${HOME_SEED_DIR}"
  install -d -m 0700 -o "${TARGET_USER}" -g "${TARGET_USER}" "${HOME_SEED_DIR}"
  rsync -aHAX --numeric-ids "${home_dir}/" "${HOME_SEED_DIR}/"

  install_units

  write_build_stamp "${dotfiles_sha}"

  log "cleaning apt caches to shrink the image"
  apt-get clean
  rm -rf /var/lib/apt/lists/*

  log "done"
}

# install_units - install the boot-time helpers and their systemd units.
#
# Packer uploads this whole directory, so the companion scripts sit next to this
# one. They are installed to /usr/local/sbin with fixed names because the unit
# files reference those paths.
install_units() {
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

  log "installing boot helpers to /usr/local/sbin"
  install -D -m 0755 "${script_dir}/seed-home.sh" /usr/local/sbin/dev-vm-seed-home
  install -D -m 0755 "${script_dir}/idle-shutdown.sh" /usr/local/sbin/dev-vm-idle-shutdown

  # Defaults live on the image; each cloud's Terraform overwrites these via
  # user_data / metadata / custom_data so thresholds and device paths are
  # tunable without rebuilding the image.
  install -d -m 0755 /etc/dev-vm
  if [[ ! -e /etc/dev-vm/seed-home.env ]]; then
    cat > /etc/dev-vm/seed-home.env << EOF
TARGET_USER=${TARGET_USER}
HOME_SEED_DIR=${HOME_SEED_DIR}
FS_LABEL=devhome
# DATA_DISK_DEVICE is left unset so the script auto-detects the single blank
# disk. Terraform sets it explicitly per cloud.
EOF
  fi
  if [[ ! -e /etc/dev-vm/idle-shutdown.env ]]; then
    cat > /etc/dev-vm/idle-shutdown.env << 'EOF'
ENABLED=true
IDLE_MINUTES=30
# Must match OnUnitActiveSec in dev-vm-idle-shutdown.timer.
CHECK_INTERVAL_MINUTES=5
LOAD_THRESHOLD=0.5
IGNORE_CONTAINERS=false
EOF
  fi

  local unit
  for unit in dev-vm-seed-home.service dev-vm-idle-shutdown.service dev-vm-idle-shutdown.timer; do
    install -D -m 0644 "${script_dir}/systemd/${unit}" "/etc/systemd/system/${unit}"
  done

  # `systemctl enable` works offline against /etc/systemd/system during an
  # image build; the units activate on the next boot.
  systemctl enable dev-vm-seed-home.service
  systemctl enable dev-vm-idle-shutdown.timer
}

# write_build_stamp <dotfiles_sha> - record what is actually on this image, so
# "which dotfiles commit is this box running?" is answerable from the box.
write_build_stamp() {
  local dotfiles_sha="$1"
  local build_time
  build_time="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  # shellcheck disable=SC1091  # os-release is generated at image build time
  local ubuntu_release=""
  if [[ -r /etc/os-release ]]; then
    ubuntu_release="$(. /etc/os-release && printf '%s' "${VERSION_ID:-unknown}")"
  fi

  log "writing ${BUILD_STAMP}"
  cat > "${BUILD_STAMP}" << EOF
{
  "dotfiles_repo": "${DOTFILES_REPO}",
  "dotfiles_ref": "${DOTFILES_REF}",
  "dotfiles_sha": "${dotfiles_sha}",
  "dotfiles_extras": "${DOTFILES_EXTRAS}",
  "ubuntu_release": "${ubuntu_release}",
  "architecture": "$(dpkg --print-architecture)",
  "kernel": "$(uname -r)",
  "target_user": "${TARGET_USER}",
  "home_seed_dir": "${HOME_SEED_DIR}",
  "build_time": "${build_time}"
}
EOF
  chmod 0644 "${BUILD_STAMP}"
}

main "$@"
