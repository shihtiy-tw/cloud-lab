#!/usr/bin/env bash
#
# cloud.security.sh - Run security scanners over infrastructure code.
#
# Usage:
#   ./scripts/cloud.security.sh --cloud aws --service compute/ecs
#   ./scripts/cloud.security.sh --cloud aws --all
#   ./scripts/cloud.security.sh --help
#
# See .opencode/command/cloud.security.md
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

readonly VALID_TOOLS=(tfsec checkov trivy all)
readonly VALID_SEVERITIES=(low medium high critical)

CLOUD=""
SERVICE=""
ALL=false
TOOL="all"
REPORT=""
MIN_SEVERITY="high"
TMP_DIR=""

declare -a RAN_TOOLS=()
declare -a RAN_STATUS=()
declare -a RAN_LOGS=()

show_help() {
  cat << EOF
Usage: $(basename "$0") --cloud <provider> --service <path> [OPTIONS]
       $(basename "$0") --cloud <provider> --all [OPTIONS]

Run static security analysis over Terraform code with tfsec, checkov, and
trivy. Repository configs (.tfsec.yml, .checkov.yml) are honoured when present.

Required:
  --cloud <provider>     Cloud provider: ${VALID_CLOUDS[*]}
                         (falls back to CLOUD_PROVIDER in .cloud-context)
  --service <path>       Service path, e.g. compute/ecs   (or use --all)

Options:
  --all                  Scan every Terraform file under the cloud directory
  --tool <tool>          ${VALID_TOOLS[*]} (default: all)
  --min-severity <level> ${VALID_SEVERITIES[*]} (default: ${MIN_SEVERITY})
  --report <file>        Write an aggregated report (.json for a JSON summary)
  --help                 Show this help message
  --version              Show version

Behaviour:
  With --tool all, every installed scanner runs and missing ones are reported
  as warnings; it only fails with exit 3 when none of them is installed. With an
  explicit --tool, a missing scanner is exit 3.

  --min-severity maps onto each scanner's native filter. Open-source checkov
  has no severity filter, so it always reports every failed check; that is
  called out in the summary rather than silently ignored.

Exit codes:
  0 no findings    2 invalid usage    3 missing dependency
  4 findings at or above --min-severity

Examples:
  $(basename "$0") --cloud aws --service compute/ecs
  $(basename "$0") --cloud aws --all --min-severity critical
  $(basename "$0") --cloud aws --service networking/vpc --tool tfsec
  $(basename "$0") --cloud aws --all --report security-report.json
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cloud)
        CLOUD="${2:-}"
        shift 2
        ;;
      --service)
        SERVICE="${2:-}"
        shift 2
        ;;
      --all)
        ALL=true
        shift
        ;;
      --tool)
        TOOL="${2:-}"
        shift 2
        ;;
      --min-severity)
        MIN_SEVERITY="${2:-}"
        shift 2
        ;;
      --report)
        REPORT="${2:-}"
        shift 2
        ;;
      --help | -h)
        show_help
        exit "${EX_OK}"
        ;;
      --version)
        print_version
        exit "${EX_OK}"
        ;;
      *)
        unknown_option "$1" || exit $?
        ;;
    esac
  done
}

cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}

# trivy_severities <min> - comma list of severities at or above min
trivy_severities() {
  case "${1}" in
    low) printf 'LOW,MEDIUM,HIGH,CRITICAL\n' ;;
    medium) printf 'MEDIUM,HIGH,CRITICAL\n' ;;
    high) printf 'HIGH,CRITICAL\n' ;;
    critical) printf 'CRITICAL\n' ;;
    *) return 1 ;;
  esac
}

# record <tool> <status> <logfile>
record() {
  RAN_TOOLS+=("$1")
  RAN_STATUS+=("$2")
  RAN_LOGS+=("$3")
}

# run_tfsec <scan-dir> - returns 0 clean, 4 findings, 1 tool error
run_tfsec() {
  local dir="$1"
  local log="${TMP_DIR}/tfsec.log"
  local -a cmd=(tfsec "${dir}" --minimum-severity "${MIN_SEVERITY^^}" --concise-output)
  if [[ -f "${REPO_ROOT}/.tfsec.yml" ]]; then
    cmd+=(--config-file "${REPO_ROOT}/.tfsec.yml")
  fi

  log_section "tfsec"
  log_info "${cmd[*]}"
  local rc=0
  "${cmd[@]}" 2>&1 | tee "${log}" || rc="${PIPESTATUS[0]}"

  if [[ "${rc}" -eq 0 ]]; then
    record tfsec clean "${log}"
    log_success "tfsec: no findings at or above ${MIN_SEVERITY}"
    return 0
  fi
  record tfsec findings "${log}"
  log_error "tfsec: findings at or above ${MIN_SEVERITY} (exit ${rc})"
  return "${EX_SECURITY}"
}

# run_checkov <scan-dir>
run_checkov() {
  local dir="$1"
  local log="${TMP_DIR}/checkov.log"
  local -a cmd=(checkov --directory "${dir}" --framework terraform --compact --quiet)
  if [[ -f "${REPO_ROOT}/.checkov.yml" ]]; then
    cmd+=(--config-file "${REPO_ROOT}/.checkov.yml")
  fi

  log_section "checkov"
  log_warn "open-source checkov has no severity filter; --min-severity does not apply here"
  log_info "${cmd[*]}"
  local rc=0
  "${cmd[@]}" 2>&1 | tee "${log}" || rc="${PIPESTATUS[0]}"

  if [[ "${rc}" -eq 0 ]]; then
    record checkov clean "${log}"
    log_success "checkov: all checks passed"
    return 0
  fi
  record checkov findings "${log}"
  log_error "checkov: failed checks (exit ${rc})"
  return "${EX_SECURITY}"
}

# run_trivy <scan-dir>
run_trivy() {
  local dir="$1"
  local log="${TMP_DIR}/trivy.log"
  local severities
  severities="$(trivy_severities "${MIN_SEVERITY}")"
  local -a cmd=(trivy config "${dir}" --severity "${severities}" --exit-code 1)

  log_section "trivy"
  log_info "${cmd[*]}"
  local rc=0
  "${cmd[@]}" 2>&1 | tee "${log}" || rc="${PIPESTATUS[0]}"

  if [[ "${rc}" -eq 0 ]]; then
    record trivy clean "${log}"
    log_success "trivy: no findings at or above ${MIN_SEVERITY}"
    return 0
  fi
  record trivy findings "${log}"
  log_error "trivy: findings at or above ${MIN_SEVERITY} (exit ${rc})"
  return "${EX_SECURITY}"
}

tool_hint() {
  case "${1}" in
    tfsec) printf 'https://github.com/aquasecurity/tfsec#installation\n' ;;
    checkov) printf 'pipx install checkov\n' ;;
    trivy) printf 'https://trivy.dev/latest/getting-started/installation/\n' ;;
    *) printf '\n' ;;
  esac
}

# write_report <target> <scan-label>
write_report() {
  local target="$1"
  local label="$2"
  local i tool status log
  local stamp
  stamp="$(utc_now)"

  if [[ "${target}" == *.json ]]; then
    {
      printf '{\n'
      printf '  "generated_at": "%s",\n' "${stamp}"
      printf '  "cloud": "%s",\n' "${CLOUD}"
      printf '  "scope": "%s",\n' "${label}"
      printf '  "min_severity": "%s",\n' "${MIN_SEVERITY}"
      printf '  "tools": [\n'
      for i in "${!RAN_TOOLS[@]}"; do
        printf '    {"tool": "%s", "status": "%s"}' "${RAN_TOOLS[${i}]}" "${RAN_STATUS[${i}]}"
        if [[ "${i}" -lt $((${#RAN_TOOLS[@]} - 1)) ]]; then
          printf ',\n'
        else
          printf '\n'
        fi
      done
      printf '  ]\n'
      printf '}\n'
    } > "${target}"
  else
    {
      printf 'Security Scan Results - %s %s\n' "${CLOUD}" "${label}"
      printf 'Generated: %s\n' "${stamp}"
      printf 'Minimum severity: %s\n' "${MIN_SEVERITY}"
      printf '=====================================\n'
      for i in "${!RAN_TOOLS[@]}"; do
        tool="${RAN_TOOLS[${i}]}"
        status="${RAN_STATUS[${i}]}"
        log="${RAN_LOGS[${i}]}"
        printf '\n%s (%s)\n' "${tool}" "${status}"
        printf -- '-------------------------------------\n'
        if [[ -f "${log}" ]]; then
          cat "${log}"
        fi
      done
    } > "${target}"
  fi
  log_success "report written to ${target}"
}

main() {
  parse_args "$@"

  local resolved
  resolved="$(resolve_cloud "${CLOUD}" || true)"
  CLOUD="${resolved}"
  validate_cloud "${CLOUD}" || exit $?

  if ! in_list "${TOOL}" "${VALID_TOOLS[@]}"; then
    die "${EX_USAGE}" "invalid --tool '${TOOL}' (expected one of: ${VALID_TOOLS[*]})"
  fi
  if ! in_list "${MIN_SEVERITY}" "${VALID_SEVERITIES[@]}"; then
    die "${EX_USAGE}" "invalid --min-severity '${MIN_SEVERITY}' (expected one of: ${VALID_SEVERITIES[*]})"
  fi
  if [[ "${ALL}" != true && -z "${SERVICE}" ]]; then
    die "${EX_USAGE}" "either --service <path> or --all is required"
  fi

  local scan_dir label
  if [[ "${ALL}" == true ]]; then
    scan_dir="${REPO_ROOT}/${CLOUD}"
    label="all"
    if [[ ! -d "${scan_dir}" ]]; then
      die "${EX_ERROR}" "cloud directory not found: ${CLOUD}/"
    fi
  else
    scan_dir="$(require_service_dir "${CLOUD}" "${SERVICE}")" || exit $?
    label="${SERVICE}"
  fi

  local tf_count
  tf_count="$(find_tf_dirs "${scan_dir}" | wc -l)"
  if [[ "${tf_count}" -eq 0 ]]; then
    log_error "no Terraform files found under ${CLOUD}/${label}"
    exit "${EX_ERROR}"
  fi
  log_info "scanning ${tf_count} Terraform director$([[ "${tf_count}" -eq 1 ]] && printf 'y' || printf 'ies') under ${CLOUD}/${label}"

  # Which scanners do we intend to run, and which are actually installed?
  local -a wanted=()
  if [[ "${TOOL}" == "all" ]]; then
    wanted=(tfsec checkov trivy)
  else
    wanted=("${TOOL}")
  fi

  local -a available=()
  local t
  for t in "${wanted[@]}"; do
    if have_cmd "${t}"; then
      available+=("${t}")
    else
      local hint
      hint="$(tool_hint "${t}")"
      if [[ "${TOOL}" == "all" ]]; then
        log_warn "${t} not installed; skipping (install: ${hint})"
      else
        log_error "required scanner not found: ${t}"
        log_error "  install: ${hint}"
        exit "${EX_DEPS}"
      fi
    fi
  done

  if [[ "${#available[@]}" -eq 0 ]]; then
    log_error "none of the security scanners are installed (${wanted[*]})"
    log_error "  install at least one, e.g.: $(tool_hint tfsec)"
    exit "${EX_DEPS}"
  fi

  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT

  log_section "Security scan - ${CLOUD} ${label}"

  local findings=0
  local rc
  for t in "${available[@]}"; do
    rc=0
    case "${t}" in
      tfsec) run_tfsec "${scan_dir}" || rc=$? ;;
      checkov) run_checkov "${scan_dir}" || rc=$? ;;
      trivy) run_trivy "${scan_dir}" || rc=$? ;;
      *) log_warn "no runner for '${t}'" ;;
    esac
    if [[ "${rc}" -ne 0 ]]; then
      findings=$((findings + 1))
    fi
  done

  log_section "Summary"
  local i
  for i in "${!RAN_TOOLS[@]}"; do
    printf '  %-10s %s\n' "${RAN_TOOLS[${i}]}" "${RAN_STATUS[${i}]}" >&2
  done

  if [[ -n "${REPORT}" ]]; then
    write_report "${REPORT}" "${label}"
  fi

  if [[ "${findings}" -gt 0 ]]; then
    log_error "${findings} of ${#available[@]} scanner(s) reported findings"
    exit "${EX_SECURITY}"
  fi
  log_success "no findings at or above ${MIN_SEVERITY} from ${#available[@]} scanner(s)"
}

main "$@"
