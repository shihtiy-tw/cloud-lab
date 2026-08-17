#!/usr/bin/env bash
#
# cloud.provision.sh - Provision cloud infrastructure with Terraform.
#
# Usage:
#   ./scripts/cloud.provision.sh --cloud aws --service compute/ecs --env dev
#   ./scripts/cloud.provision.sh --cloud aws --service networking/vpc --env dev --plan-only
#   ./scripts/cloud.provision.sh --help
#
# See .opencode/command/cloud.provision.md
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

readonly MIN_TERRAFORM_VERSION="1.5.0"

CLOUD=""
SERVICE=""
ENVIRONMENT=""
PLAN_ONLY=false
DESTROY=false
AUTO_APPROVE=false
CONFIRMED=false
WORKSPACE=""
PLAN_OUT=""
declare -a EXTRA_VARS=()
TMP_PLAN_DIR=""

show_help() {
  cat <<EOF
Usage: $(basename "$0") --cloud <provider> --service <path> --env <environment> [OPTIONS]

Provision cloud infrastructure with Terraform. The plan is always generated and
shown before anything is applied, and the saved plan file is what gets applied,
so the applied change is exactly the reviewed one.

Required:
  --cloud <provider>     Cloud provider: ${VALID_CLOUDS[*]}
                         (falls back to CLOUD_PROVIDER in .cloud-context)
  --service <path>       Service path under the cloud dir, e.g. compute/ecs
  --env <environment>    Environment: ${VALID_ENVS[*]}

Options:
  --plan-only            Show the plan and stop; nothing is applied
  --destroy              Destroy the stack instead of applying
  --auto-approve         Skip the interactive prompt (never for prod destroy)
  --confirm              Required acknowledgement for prod and for --destroy
  --var KEY=VALUE        Extra Terraform variable; repeatable
  --out <file>           Save the plan file (default: a temp file, discarded)
  --workspace <name>     Select this Terraform workspace (creating it if needed)
  --help                 Show this help message
  --version              Show version

Safety model:
  prod apply       requires --confirm, plus a prompt unless --auto-approve
  destroy          requires --confirm, plus typing an exact confirmation phrase
  prod destroy     requires --confirm and the phrase; --auto-approve cannot skip it

What --env actually does:
  It selects <env>.tfvars when that file exists, and passes environment=<env>
  when the stack declares that variable. It deliberately does NOT pick a
  Terraform workspace: most aws/ stacks here read terraform.workspace as the AWS
  *region* (region = terraform.workspace), so a workspace named 'dev' would fail
  with "Invalid AWS Region: dev". Use --workspace to control that explicitly.

Service paths:
  A service may hold several Terraform roots (aws/compute/ecs has one per
  scenario). When the path is ambiguous the candidates are listed so you can
  pass a deeper --service, e.g.:
    --service compute/ecs/infrastructure/cluster

Exit codes:
  0 success    1 error    2 invalid usage    3 missing dependency

Examples:
  $(basename "$0") --cloud aws --service compute/ecs/infrastructure/cluster --env dev
  $(basename "$0") --cloud aws --service compute/ecs/scenarios/ecs-fargate-service-with-alb --env dev --plan-only
  $(basename "$0") --cloud aws --service networking/vpc --env prod --confirm
  $(basename "$0") --cloud aws --service compute/ecs --env dev --destroy --confirm
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
      --env | --environment)
        ENVIRONMENT="${2:-}"
        shift 2
        ;;
      --plan-only | --plan)
        PLAN_ONLY=true
        shift
        ;;
      --destroy)
        DESTROY=true
        shift
        ;;
      --auto-approve)
        AUTO_APPROVE=true
        shift
        ;;
      --confirm)
        CONFIRMED=true
        shift
        ;;
      --var)
        if [[ -z "${2:-}" ]]; then
          log_error "--var requires a KEY=VALUE argument"
          exit "${EX_USAGE}"
        fi
        if [[ ! "${2}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
          log_error "--var expects KEY=VALUE, got: ${2}"
          exit "${EX_USAGE}"
        fi
        EXTRA_VARS+=("${2}")
        shift 2
        ;;
      --out)
        PLAN_OUT="${2:-}"
        shift 2
        ;;
      --workspace)
        WORKSPACE="${2:-}"
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
  if [[ -n "${TMP_PLAN_DIR}" && -d "${TMP_PLAN_DIR}" ]]; then
    rm -rf "${TMP_PLAN_DIR}"
  fi
}

# check_terraform_version - warn when older than the documented minimum
check_terraform_version() {
  local version
  version="$(terraform version -json 2>/dev/null |
    grep -o '"terraform_version"[[:space:]]*:[[:space:]]*"[^"]*"' |
    head -1 | sed 's/.*"\([0-9][^"]*\)"$/\1/')" || true
  if [[ -z "${version}" ]]; then
    log_warn "could not determine the Terraform version; continuing"
    return 0
  fi
  log_info "terraform ${version}"
  local lowest
  lowest="$(printf '%s\n%s\n' "${version}" "${MIN_TERRAFORM_VERSION}" | sort -V | head -1)"
  if [[ "${version}" != "${MIN_TERRAFORM_VERSION}" && "${lowest}" == "${version}" ]]; then
    log_warn "Terraform ${version} is older than the required ${MIN_TERRAFORM_VERSION}"
  fi
  return 0
}

# warn_on_local_state <dir> - flag stacks with no remote backend configured
warn_on_local_state() {
  local dir="$1"
  if grep -rlqs --include='*.tf' 'backend[[:space:]]*"' "${dir}" ||
    grep -rlqs --include='*.tf' 'cloud[[:space:]]*{' "${dir}"; then
    return 0
  fi
  local backend
  backend="$(tf_backend_hint "${CLOUD}")"
  log_warn "no remote backend configured in this stack; state will be local"
  log_warn "  expected for ${CLOUD}: ${backend}"
  return 0
}

# select_workspace <dir> <name>
select_workspace() {
  local dir="$1"
  local name="$2"
  log_info "selecting Terraform workspace '${name}'"
  if terraform -chdir="${dir}" workspace select "${name}" >/dev/null 2>&1; then
    return 0
  fi
  log_info "workspace '${name}' does not exist; creating it"
  if terraform -chdir="${dir}" workspace new "${name}" >/dev/null 2>&1; then
    return 0
  fi
  log_warn "could not select or create workspace '${name}'; using the current workspace"
  return 0
}

# warn_workspace_convention <dir> - these stacks read terraform.workspace as the
# AWS region, so the active workspace changes where resources land.
warn_workspace_convention() {
  local dir="$1"
  if ! grep -rlqs --include='*.tf' 'region[[:space:]]*=[[:space:]]*terraform\.workspace' "${dir}"; then
    return 0
  fi
  local current
  current="$(terraform -chdir="${dir}" workspace show 2>/dev/null || printf 'unknown\n')"
  log_warn "this stack sets 'region = terraform.workspace': the workspace name IS the AWS region"
  log_warn "  active workspace: ${current}"
  if [[ -z "${WORKSPACE}" ]]; then
    log_warn "  pass --workspace <aws-region> (e.g. --workspace us-east-1) to target a region"
  fi
  return 0
}

# build_var_args <dir> <env> - emit terraform -var-file/-var arguments, one per line
build_var_args() {
  local dir="$1"
  local env="$2"
  local candidate
  for candidate in "${env}.tfvars" "${env}.tfvars.json" "terraform.tfvars"; do
    if [[ -f "${dir}/${candidate}" ]]; then
      printf -- '-var-file=%s\n' "${dir}/${candidate}"
      log_info "using variable file ${candidate}"
    fi
  done
  local kv
  for kv in ${EXTRA_VARS[@]+"${EXTRA_VARS[@]}"}; do
    printf -- '-var\n%s\n' "${kv}"
  done
  # Environment is a near-universal input in this repo; pass it when declared.
  if grep -rlqs --include='*.tf' 'variable[[:space:]]*"environment"' "${dir}"; then
    printf -- '-var\nenvironment=%s\n' "${env}"
  fi
}

# gate_apply <target-label> - enforce the confirmation policy
gate_apply() {
  local label="$1"

  if [[ "${DESTROY}" == true ]]; then
    if [[ "${CONFIRMED}" != true ]]; then
      log_error "--destroy requires --confirm as an explicit acknowledgement"
      return "${EX_USAGE}"
    fi
    local phrase="destroy ${label}"
    if [[ "${ENVIRONMENT}" == "prod" ]]; then
      log_warn "PRODUCTION DESTROY requested; --auto-approve does not apply here"
      if ! confirm "Type exactly '${phrase}' to proceed:" "${phrase}"; then
        log_error "confirmation phrase did not match; aborting"
        return "${EX_ERROR}"
      fi
      return 0
    fi
    if [[ "${AUTO_APPROVE}" == true ]]; then
      log_warn "--auto-approve given; skipping the destroy confirmation phrase"
      return 0
    fi
    if ! confirm "Type exactly '${phrase}' to proceed:" "${phrase}"; then
      log_error "confirmation phrase did not match; aborting"
      return "${EX_ERROR}"
    fi
    return 0
  fi

  if [[ "${ENVIRONMENT}" == "prod" && "${CONFIRMED}" != true ]]; then
    log_error "applying to prod requires --confirm"
    return "${EX_USAGE}"
  fi

  if [[ "${AUTO_APPROVE}" == true ]]; then
    return 0
  fi

  if ! confirm "Apply this plan to ${label}? [yes/no]:" "yes"; then
    log_error "not confirmed; aborting"
    return "${EX_ERROR}"
  fi
  return 0
}

main() {
  parse_args "$@"

  require_cmd terraform "https://developer.hashicorp.com/terraform/downloads" || exit $?

  local resolved
  resolved="$(resolve_cloud "${CLOUD}" || true)"
  CLOUD="${resolved}"
  validate_cloud "${CLOUD}" || exit $?
  validate_env "${ENVIRONMENT}" || exit $?

  if [[ "${PLAN_ONLY}" == true && "${DESTROY}" == true ]]; then
    log_info "--plan-only with --destroy: showing the destroy plan without applying"
  fi

  local svc_dir
  svc_dir="$(require_service_dir "${CLOUD}" "${SERVICE}")" || exit $?

  local tf_dir
  if ! tf_dir="$(resolve_tf_dir "${svc_dir}")"; then
    report_tf_candidates "${CLOUD}" "${SERVICE}" "${svc_dir}"
    exit "${EX_USAGE}"
  fi

  local label="${CLOUD}/${SERVICE} (${ENVIRONMENT})"
  log_section "Provision ${label}"
  log_info "terraform root: ${tf_dir#"${REPO_ROOT}"/}"

  check_terraform_version

  # Export the saved provider context so Terraform picks up profile/project/region.
  if context_load; then
    log_info "loaded provider context from ${CONTEXT_FILE#"${REPO_ROOT}"/}"
  else
    log_warn "no .cloud-context found; relying on the ambient environment"
  fi

  local cli
  cli="$(csp_cli "${CLOUD}")"
  if ! have_cmd "${cli}"; then
    local hint
    hint="$(csp_cli_hint "${CLOUD}")"
    log_warn "${cli} CLI not found; Terraform may fail to authenticate"
    log_warn "  install: ${hint}"
  fi

  warn_on_local_state "${tf_dir}"

  log_section "terraform init"
  terraform -chdir="${tf_dir}" init -input=false

  if [[ -n "${WORKSPACE}" ]]; then
    select_workspace "${tf_dir}" "${WORKSPACE}"
  fi
  warn_workspace_convention "${tf_dir}"

  log_section "terraform validate"
  terraform -chdir="${tf_dir}" validate

  local -a var_args=()
  local arg
  while IFS= read -r arg; do
    var_args+=("${arg}")
  done < <(build_var_args "${tf_dir}" "${ENVIRONMENT}")

  # Save the plan so the apply step consumes exactly what was reviewed.
  local plan_file
  if [[ -n "${PLAN_OUT}" ]]; then
    plan_file="${PLAN_OUT}"
  else
    TMP_PLAN_DIR="$(mktemp -d)"
    trap cleanup EXIT
    plan_file="${TMP_PLAN_DIR}/${ENVIRONMENT}.tfplan"
  fi

  local -a plan_cmd=(terraform -chdir="${tf_dir}" plan -input=false -out="${plan_file}")
  if [[ "${DESTROY}" == true ]]; then
    plan_cmd+=(-destroy)
  fi
  plan_cmd+=(-detailed-exitcode)
  plan_cmd+=(${var_args[@]+"${var_args[@]}"})

  log_section "terraform plan"
  local plan_rc=0
  "${plan_cmd[@]}" || plan_rc=$?

  case "${plan_rc}" in
    0)
      log_success "no changes; infrastructure matches the configuration"
      if [[ -n "${PLAN_OUT}" ]]; then
        log_info "plan saved to ${plan_file}"
      fi
      exit "${EX_OK}"
      ;;
    2)
      log_info "plan produced changes"
      ;;
    *)
      die "${EX_ERROR}" "terraform plan failed (exit ${plan_rc})"
      ;;
  esac

  if [[ -n "${PLAN_OUT}" ]]; then
    log_success "plan saved to ${plan_file}"
    log_info "estimate its cost with: ./scripts/cloud.cost.sh --cloud ${CLOUD} --estimate --plan ${plan_file}"
  fi

  if [[ "${PLAN_ONLY}" == true ]]; then
    log_success "--plan-only: stopping before apply"
    exit "${EX_OK}"
  fi

  gate_apply "${label}" || exit $?

  if [[ "${DESTROY}" == true ]]; then
    log_section "terraform apply (destroy plan)"
  else
    log_section "terraform apply"
  fi
  terraform -chdir="${tf_dir}" apply -input=false "${plan_file}"

  if [[ "${DESTROY}" != true ]]; then
    log_section "outputs"
    terraform -chdir="${tf_dir}" output || log_warn "no outputs defined"
  fi

  log_success "done: ${label}"
}

main "$@"
