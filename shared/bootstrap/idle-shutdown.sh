#!/usr/bin/env bash
#
# Shut the VM down when nobody is using it.
#
# This is the on-box half of the auto-stop design. Each cloud also has a
# scheduled hard stop (EventBridge Scheduler on AWS, an instance schedule policy
# on GCP, a DevTest shutdown schedule on Azure) as a backstop, because an on-box
# timer cannot save you if the box wedges. This script is the part that reacts to
# actual idleness rather than to the clock.
#
# "Idle" deliberately means more than "no TTY": a long compile or a running
# container is work in progress even with no one attached. A shutdown here is
# cheap to recover from -- the home directory is on a persistent disk -- but
# killing a 40-minute build would still be obnoxious.
#
# Runs as root from dev-vm-idle-shutdown.timer. Reads
# /etc/dev-vm/idle-shutdown.env so the threshold is tunable per cloud from
# Terraform without rebuilding the image.
#
# Environment (defaults shown):
#   IDLE_MINUTES=30          consecutive idle checks required, in minutes
#   CHECK_INTERVAL_MINUTES=5 must match the timer's OnUnitActiveSec
#   LOAD_THRESHOLD=0.5       1-minute load average below which the box is idle
#   IGNORE_CONTAINERS=false  set true to ignore running containers
#   ENABLED=true             set false to disable without masking the timer

set -euo pipefail

readonly CONFIG_FILE="/etc/dev-vm/idle-shutdown.env"
readonly STATE_FILE="/var/lib/dev-vm/idle-counter"

# shellcheck source=/dev/null
[[ -r ${CONFIG_FILE} ]] && . "${CONFIG_FILE}"

readonly IDLE_MINUTES="${IDLE_MINUTES:-30}"
readonly CHECK_INTERVAL_MINUTES="${CHECK_INTERVAL_MINUTES:-5}"
readonly LOAD_THRESHOLD="${LOAD_THRESHOLD:-0.5}"
readonly IGNORE_CONTAINERS="${IGNORE_CONTAINERS:-false}"
readonly ENABLED="${ENABLED:-true}"

log() { printf '[idle-shutdown] %s\n' "$*" >&2; }

# has_interactive_session - any human attached, by any route. Session Manager,
# IAP and Bastion all end up as either a login session or an sshd/ssm child, so
# check both rather than assuming a TTY exists.
has_interactive_session() {
  # loginctl sees SSM/IAP/Bastion logins that allocate a session.
  if command -v loginctl > /dev/null 2>&1; then
    if [[ "$(loginctl list-sessions --no-legend 2> /dev/null | wc -l)" -gt 0 ]]; then
      return 0
    fi
  fi

  # `who` catches plain pty logins.
  if [[ -n "$(who 2> /dev/null)" ]]; then
    return 0
  fi

  # SSM shell sessions do not always register with logind; the agent forks a
  # ssm-session-worker per active session.
  if pgrep -f 'ssm-session-worker' > /dev/null 2>&1; then
    return 0
  fi

  return 1
}

# has_active_work - long-running things a user would be upset to lose.
has_active_work() {
  # tmux/screen sessions mean detached work the user intends to come back to.
  if pgrep -x 'tmux: server' > /dev/null 2>&1 || pgrep -x screen > /dev/null 2>&1; then
    log "tmux or screen session present"
    return 0
  fi

  # Builds and package managers.
  if pgrep -x 'make|cargo|go|gcc|cc1|rustc|npm|pnpm|yarn|apt|dpkg|terraform|packer' > /dev/null 2>&1; then
    log "build or package process running"
    return 0
  fi

  if [[ ${IGNORE_CONTAINERS} != "true" ]] && has_running_containers; then
    log "containers running"
    return 0
  fi

  if load_above_threshold; then
    log "load average above ${LOAD_THRESHOLD}"
    return 0
  fi

  return 1
}

# has_running_containers - a kind/k3d cluster or any docker workload counts as
# active. Docker is present because upstream `make install` installs it.
has_running_containers() {
  command -v docker > /dev/null 2>&1 || return 1
  local count
  count="$(docker ps --quiet 2> /dev/null | wc -l)" || return 1
  [[ ${count} -gt 0 ]]
}

# load_above_threshold - compares the 1-minute load average without needing bc,
# which is not installed on a minimal cloud image.
load_above_threshold() {
  local load1
  load1="$(cut -d' ' -f1 /proc/loadavg)"
  awk -v load="${load1}" -v threshold="${LOAD_THRESHOLD}" \
    'BEGIN { exit !(load > threshold) }'
}

read_counter() {
  if [[ -r ${STATE_FILE} ]]; then
    local value
    value="$(cat "${STATE_FILE}")"
    # A corrupt state file must not wedge the timer forever.
    if [[ ${value} =~ ^[0-9]+$ ]]; then
      printf '%s' "${value}"
      return 0
    fi
  fi
  printf '0'
}

write_counter() {
  install -d -m 0755 "$(dirname "${STATE_FILE}")"
  printf '%s' "$1" > "${STATE_FILE}"
}

main() {
  if [[ ${ENABLED} != "true" ]]; then
    log "disabled via ${CONFIG_FILE}; nothing to do"
    return 0
  fi

  if has_interactive_session; then
    log "interactive session present; resetting idle counter"
    write_counter 0
    return 0
  fi

  if has_active_work; then
    log "active work detected; resetting idle counter"
    write_counter 0
    return 0
  fi

  local counter
  counter="$(read_counter)"
  counter=$((counter + CHECK_INTERVAL_MINUTES))
  write_counter "${counter}"

  if [[ ${counter} -ge ${IDLE_MINUTES} ]]; then
    log "idle for ${counter}m (threshold ${IDLE_MINUTES}m); shutting down"
    # Reset first: if the stop is later cancelled or the box is restarted by
    # the cloud, a stale counter would shut it down again immediately.
    write_counter 0
    # `poweroff` maps to the cloud's stop, so the persistent disk detaches
    # cleanly and billing for compute ends.
    systemctl poweroff
    return 0
  fi

  log "idle for ${counter}m of ${IDLE_MINUTES}m"
}

main "$@"
