#!/usr/bin/env bash
#
# cloud.switch.sh - Switch the active cloud provider context.
#
# Usage:
#   ./scripts/cloud.switch.sh --cloud aws --profile staging --region us-west-2
#   ./scripts/cloud.switch.sh --show
#   ./scripts/cloud.switch.sh --help
#
# See .opencode/command/cloud.switch.md
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CLOUD=""
SHOW=false
EXPORT_MODE=false
VERIFY_STRICT=false
APPLY_CLI_CONFIG=false
PROFILE=""
REGION=""
PROJECT=""
SUBSCRIPTION=""
RESOURCE_GROUP=""
COMPARTMENT=""

show_help() {
  cat <<EOF
Usage: $(basename "$0") --cloud <provider> [OPTIONS]
       $(basename "$0") --show [--export]

Switch the active cloud provider context for subsequent cloud-lab commands.
The context is persisted to .cloud-context at the repository root and read by
the other scripts/cloud.*.sh commands.

Options:
  --cloud <provider>     Cloud provider: ${VALID_CLOUDS[*]} (required unless --show)
  --show                 Display the current context and exit
  --export               With --show, emit 'export K=V' lines for eval
  --verify               Treat a failed credential check as an error
  --apply-cli-config     Also mutate the provider CLI's own global config
  --help                 Show this help message
  --version              Show version

Provider-specific options:
  AWS      --profile <name>        --region <region>
  GCP      --project <id>          --region <region>
  Azure    --subscription <id>     --rg <resource-group>
  Oracle   --profile <name>        --region <region>   --compartment <ocid>

Behaviour notes:
  Credentials are checked on a best-effort basis: a missing provider CLI or an
  unauthenticated session is reported as a warning, because setting context
  before installing or logging in is legitimate. Pass --verify to make those
  conditions fatal.

  By default only .cloud-context is written; the provider CLI's global config
  is left alone. --apply-cli-config opts into mutating it (e.g. 'gcloud config
  set project', 'az account set').

To load the context into your own shell:
  eval "\$(./scripts/cloud.switch.sh --show --export)"

Exit codes:
  0 success    2 invalid usage    3 missing dependency (--verify)    1 other

Examples:
  $(basename "$0") --cloud aws --profile staging --region us-west-2
  $(basename "$0") --cloud gcp --project my-project-123 --region us-central1
  $(basename "$0") --cloud azure --subscription 00000000-0000-0000-0000-000000000000 --rg prod-rg
  $(basename "$0") --cloud oracle --profile DEFAULT --region us-ashburn-1
  $(basename "$0") --show
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cloud)
        CLOUD="${2:-}"
        shift 2
        ;;
      --show)
        SHOW=true
        shift
        ;;
      --export)
        EXPORT_MODE=true
        shift
        ;;
      --verify)
        VERIFY_STRICT=true
        shift
        ;;
      --apply-cli-config)
        APPLY_CLI_CONFIG=true
        shift
        ;;
      --profile)
        PROFILE="${2:-}"
        shift 2
        ;;
      --region)
        REGION="${2:-}"
        shift 2
        ;;
      --project)
        PROJECT="${2:-}"
        shift 2
        ;;
      --subscription)
        SUBSCRIPTION="${2:-}"
        shift 2
        ;;
      --rg | --resource-group)
        RESOURCE_GROUP="${2:-}"
        shift 2
        ;;
      --compartment)
        COMPARTMENT="${2:-}"
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

# show_context - print the saved context, optionally as shell exports
show_context() {
  if [[ ! -f "${CONTEXT_FILE}" ]]; then
    if [[ "${EXPORT_MODE}" == true ]]; then
      # Nothing to eval; stay silent on stdout so eval is a no-op.
      log_warn "no context set (run: $(basename "$0") --cloud <provider>)"
      return "${EX_OK}"
    fi
    log_warn "no active context; .cloud-context does not exist"
    log_warn "  set one with: $(basename "$0") --cloud aws"
    return "${EX_OK}"
  fi

  if [[ "${EXPORT_MODE}" == true ]]; then
    # Emit only well-formed KEY=VALUE lines, shell-quoted.
    local line key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
      if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        printf 'export %s=%q\n' "${key}" "${value}"
      fi
    done <"${CONTEXT_FILE}"
    return "${EX_OK}"
  fi

  printf 'Active cloud context (%s)\n' "${CONTEXT_FILE#"${REPO_ROOT}"/}"
  printf -- '---------------------------------------------\n'
  local line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      printf '  %-28s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    fi
  done <"${CONTEXT_FILE}"
  return "${EX_OK}"
}

# verify_credentials <cloud> - best-effort auth probe
# Returns: 0 ok, EX_DEPS missing CLI, EX_ERROR CLI present but unauthenticated
verify_credentials() {
  local cloud="$1"
  local cli
  cli="$(csp_cli "${cloud}")"

  if ! have_cmd "${cli}"; then
    local hint
    hint="$(csp_cli_hint "${cloud}")"
    log_warn "${cli} CLI not installed; skipping credential check"
    log_warn "  install: ${hint}"
    return "${EX_DEPS}"
  fi

  log_info "verifying ${cloud} credentials with ${cli}..."
  local ok=true
  case "${cloud}" in
    aws)
      aws sts get-caller-identity >/dev/null 2>&1 || ok=false
      ;;
    gcp)
      local active_account=""
      active_account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"
      if [[ -z "${active_account}" ]]; then
        ok=false
      fi
      ;;
    azure)
      az account show >/dev/null 2>&1 || ok=false
      ;;
    oracle)
      oci iam region list >/dev/null 2>&1 || ok=false
      ;;
    *)
      log_warn "no credential check defined for '${cloud}'"
      return "${EX_OK}"
      ;;
  esac

  if [[ "${ok}" == true ]]; then
    log_success "${cloud} credentials verified"
    return "${EX_OK}"
  fi

  log_warn "${cli} is installed but no usable credentials were found"
  case "${cloud}" in
    aws) log_warn "  try: aws configure --profile <name>" ;;
    gcp) log_warn "  try: gcloud auth login && gcloud auth application-default login" ;;
    azure) log_warn "  try: az login" ;;
    oracle) log_warn "  try: oci setup config" ;;
    *) ;;
  esac
  return "${EX_ERROR}"
}

# apply_cli_config <cloud> - opt-in mutation of the provider CLI's own config
apply_cli_config() {
  local cloud="$1"
  local cli
  cli="$(csp_cli "${cloud}")"
  if ! have_cmd "${cli}"; then
    log_warn "--apply-cli-config requested but ${cli} is not installed; skipping"
    return "${EX_OK}"
  fi

  case "${cloud}" in
    gcp)
      if [[ -n "${PROJECT}" ]]; then
        log_info "gcloud config set project ${PROJECT}"
        gcloud config set project "${PROJECT}" >/dev/null 2>&1 ||
          log_warn "gcloud config set project failed"
      fi
      if [[ -n "${REGION}" ]]; then
        log_info "gcloud config set compute/region ${REGION}"
        gcloud config set compute/region "${REGION}" >/dev/null 2>&1 ||
          log_warn "gcloud config set compute/region failed"
      fi
      ;;
    azure)
      if [[ -n "${SUBSCRIPTION}" ]]; then
        log_info "az account set --subscription ${SUBSCRIPTION}"
        az account set --subscription "${SUBSCRIPTION}" >/dev/null 2>&1 ||
          log_warn "az account set failed"
      fi
      ;;
    aws | oracle)
      # Both are driven entirely by environment variables; nothing global to set.
      log_info "no global CLI config needed for ${cloud} (environment variables suffice)"
      ;;
    *) ;;
  esac
  return "${EX_OK}"
}

# build_context <cloud> - assemble the KEY=VALUE lines for .cloud-context
build_context() {
  local cloud="$1"
  local -a kv=("CLOUD_PROVIDER=${cloud}")

  case "${cloud}" in
    aws)
      kv+=("AWS_PROFILE=${PROFILE:-default}")
      kv+=("AWS_DEFAULT_REGION=${REGION:-us-east-1}")
      kv+=("AWS_REGION=${REGION:-us-east-1}")
      ;;
    gcp)
      kv+=("CLOUDSDK_CORE_PROJECT=${PROJECT}")
      kv+=("CLOUDSDK_COMPUTE_REGION=${REGION:-us-central1}")
      kv+=("GOOGLE_PROJECT=${PROJECT}")
      kv+=("GOOGLE_REGION=${REGION:-us-central1}")
      ;;
    azure)
      kv+=("AZURE_SUBSCRIPTION_ID=${SUBSCRIPTION}")
      # The azurerm Terraform provider reads the ARM_* form.
      kv+=("ARM_SUBSCRIPTION_ID=${SUBSCRIPTION}")
      kv+=("AZURE_RESOURCE_GROUP=${RESOURCE_GROUP}")
      ;;
    oracle)
      kv+=("OCI_CLI_PROFILE=${PROFILE:-DEFAULT}")
      kv+=("OCI_CLI_REGION=${REGION:-us-ashburn-1}")
      kv+=("OCI_COMPARTMENT_OCID=${COMPARTMENT}")
      ;;
    *) ;;
  esac

  printf '%s\n' "${kv[@]}"
}

# warn_missing_recommended <cloud> - flag provider settings that matter
warn_missing_recommended() {
  local cloud="$1"
  case "${cloud}" in
    gcp)
      if [[ -z "${PROJECT}" ]]; then
        log_warn "no --project given; GCP Terraform runs will fail without a project id"
      fi
      ;;
    azure)
      if [[ -z "${SUBSCRIPTION}" ]]; then
        log_warn "no --subscription given; Azure Terraform runs will fail without a subscription id"
      fi
      ;;
    oracle)
      if [[ -z "${COMPARTMENT}" ]]; then
        log_warn "no --compartment given; most OCI resources require a compartment OCID"
      fi
      ;;
    aws) ;;
    *) ;;
  esac
}

main() {
  parse_args "$@"

  if [[ "${SHOW}" == true ]]; then
    show_context
    exit $?
  fi

  validate_cloud "${CLOUD}" || exit $?

  local cloud_dir="${REPO_ROOT}/${CLOUD}"
  if [[ ! -d "${cloud_dir}" ]]; then
    die "${EX_ERROR}" "cloud directory not found: ${CLOUD}/"
  fi

  warn_missing_recommended "${CLOUD}"

  local -a context_lines=()
  local line
  while IFS= read -r line; do
    context_lines+=("${line}")
  done < <(build_context "${CLOUD}")

  context_save "${context_lines[@]}"
  log_success "context set to ${CLOUD} (${CONTEXT_FILE#"${REPO_ROOT}"/})"

  if [[ "${APPLY_CLI_CONFIG}" == true ]]; then
    apply_cli_config "${CLOUD}"
  fi

  local verify_rc=0
  verify_credentials "${CLOUD}" || verify_rc=$?
  if [[ "${verify_rc}" -ne 0 && "${VERIFY_STRICT}" == true ]]; then
    die "${verify_rc}" "--verify was requested and the credential check failed"
  fi

  # Terraform state lives per-provider; remind the operator what it expects.
  local backend
  backend="$(tf_backend_hint "${CLOUD}")"
  log_info "expected remote state backend for ${CLOUD}: ${backend}"

  show_context
}

main "$@"
