#!/usr/bin/env bash
#
# common.sh - Shared helpers for the cloud-lab operational scripts.
#
# Sourced by scripts/cloud.*.sh; it is not meant to be executed directly.
# Contracts implemented here come from .specify/002-scripts/ and the command
# documentation in .opencode/command/cloud.*.md.
#

if [[ -n "${_CLOUD_LAB_COMMON_LOADED:-}" ]]; then
  return 0
fi
_CLOUD_LAB_COMMON_LOADED=1

# --- Paths -------------------------------------------------------------------

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR
SCRIPTS_DIR="$(dirname "${LIB_DIR}")"
readonly SCRIPTS_DIR
REPO_ROOT="$(dirname "${SCRIPTS_DIR}")"
readonly REPO_ROOT

readonly CONTEXT_FILE="${REPO_ROOT}/.cloud-context"
readonly CLOUD_LAB_VERSION="1.0.0"

# --- Exit codes (.specify/002-scripts/data-model.md) -------------------------

readonly EX_OK=0
readonly EX_ERROR=1
readonly EX_USAGE=2
readonly EX_DEPS=3
readonly EX_SECURITY=4

# --- Vocabulary --------------------------------------------------------------

readonly VALID_CLOUDS=(aws gcp azure oracle)
readonly VALID_CATEGORIES=(compute storage database networking security monitoring)
readonly VALID_ENVS=(dev staging test prod)

# --- Logging -----------------------------------------------------------------
#
# Every log line goes to stderr so that stdout stays reserved for data the
# caller may want to pipe (cost tables, generated docs, resolved paths).

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  readonly C_RED=$'\033[0;31m'
  readonly C_GREEN=$'\033[0;32m'
  readonly C_YELLOW=$'\033[1;33m'
  readonly C_BLUE=$'\033[0;34m'
  readonly C_BOLD=$'\033[1m'
  readonly C_NC=$'\033[0m'
else
  readonly C_RED=''
  readonly C_GREEN=''
  readonly C_YELLOW=''
  readonly C_BLUE=''
  readonly C_BOLD=''
  readonly C_NC=''
fi

log_info() { printf '%s[INFO]%s %s\n' "${C_BLUE}" "${C_NC}" "$*" >&2; }
log_success() { printf '%s[OK]%s %s\n' "${C_GREEN}" "${C_NC}" "$*" >&2; }
log_warn() { printf '%s[WARN]%s %s\n' "${C_YELLOW}" "${C_NC}" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "${C_RED}" "${C_NC}" "$*" >&2; }
log_section() { printf '\n%s=== %s ===%s\n\n' "${C_BOLD}" "$*" "${C_NC}" >&2; }

log_debug() {
  if [[ -n "${CLOUD_LAB_DEBUG:-}" ]]; then
    printf '[DEBUG] %s\n' "$*" >&2
  fi
}

# die <exit-code> <message...>
die() {
  local code="$1"
  shift
  log_error "$@"
  exit "${code}"
}

# --- Small utilities ---------------------------------------------------------

# in_list <needle> <haystack...>
in_list() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

have_cmd() { command -v "$1" > /dev/null 2>&1; }

# require_cmd <command> [install-hint]
# Returns EX_DEPS when the command is missing so callers can `|| exit $?`.
require_cmd() {
  local cmd="$1"
  local hint="${2:-}"
  if have_cmd "${cmd}"; then
    return 0
  fi
  log_error "required command not found: ${cmd}"
  if [[ -n "${hint}" ]]; then
    log_error "  install: ${hint}"
  fi
  return "${EX_DEPS}"
}

utc_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# --- Environment file --------------------------------------------------------
#
# Loads ${REPO_ROOT}/.env so credentials and TF_VAR_/PKR_VAR_ inputs live in one
# gitignored file instead of being hardcoded in Terraform or retyped per command.
# See .env.example for the documented set.
#
# Two deliberate choices:
#
#   1. The file is *sourced*, not parsed as inert KEY=VALUE. That is what lets a
#      value come from a secret store at use time --
#      `export ARM_CLIENT_SECRET="$(op read ...)"` -- instead of sitting in
#      plaintext on disk. The cost is that .env runs as shell; it is gitignored
#      and user-authored, so that is an acceptable trade, but it is a real one.
#
#   2. An already-set variable beats the file. This matches every other dotenv
#      loader and keeps one-off overrides working:
#      `AWS_PROFILE=other ./scripts/cloud.cost.sh --cloud aws`. Without it, .env
#      would silently win and the override would look broken.
load_dotenv() {
  local env_file="${CLOUD_LAB_ENV_FILE:-${REPO_ROOT}/.env}"

  if [[ ! -f "${env_file}" ]]; then
    log_debug "no env file at ${env_file}"
    return 0
  fi

  # Names the file assigns, so their pre-existing values can be put back after.
  local -a names=()
  local name
  while IFS= read -r name; do
    [[ -n "${name}" ]] && names+=("${name}")
  done < <(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p' "${env_file}" | sort -u)

  local -a restore=()
  for name in "${names[@]+"${names[@]}"}"; do
    if [[ -n "${!name+x}" ]]; then
      restore+=("${name}=${!name}")
    fi
  done

  set -a
  # shellcheck source=/dev/null
  source "${env_file}"
  set +a

  local kv
  for kv in "${restore[@]+"${restore[@]}"}"; do
    export "${kv?}"
  done

  log_debug "loaded ${env_file} (${#names[@]} names, ${#restore[@]} kept from the environment)"
}

load_dotenv

# confirm <prompt> [expected-answer]
# Requires an interactive terminal; refuses rather than assuming consent.
confirm() {
  local prompt="$1"
  local expected="${2:-yes}"
  local reply
  if [[ ! -t 0 ]]; then
    log_error "confirmation required but stdin is not a terminal"
    log_error "  re-run interactively, or pass --auto-approve if the risk is understood"
    return 1
  fi
  printf '%s%s%s ' "${C_BOLD}" "${prompt}" "${C_NC}" >&2
  read -r reply
  [[ "${reply}" == "${expected}" ]]
}

# --- Validation --------------------------------------------------------------

validate_cloud() {
  local cloud="${1:-}"
  if [[ -z "${cloud}" ]]; then
    log_error "--cloud is required (one of: ${VALID_CLOUDS[*]})"
    log_error "  tip: 'make aws' (or gcp/azure/oracle) sets a default in .cloud-context"
    return "${EX_USAGE}"
  fi
  if ! in_list "${cloud}" "${VALID_CLOUDS[@]}"; then
    log_error "unsupported cloud '${cloud}' (expected one of: ${VALID_CLOUDS[*]})"
    return "${EX_USAGE}"
  fi
  return 0
}

validate_category() {
  local category="${1:-}"
  if [[ -z "${category}" ]]; then
    log_error "--category is required (one of: ${VALID_CATEGORIES[*]})"
    return "${EX_USAGE}"
  fi
  if ! in_list "${category}" "${VALID_CATEGORIES[@]}"; then
    log_error "unsupported category '${category}' (expected one of: ${VALID_CATEGORIES[*]})"
    return "${EX_USAGE}"
  fi
  return 0
}

validate_env() {
  local env="${1:-}"
  if [[ -z "${env}" ]]; then
    log_error "--env is required (one of: ${VALID_ENVS[*]})"
    return "${EX_USAGE}"
  fi
  if ! in_list "${env}" "${VALID_ENVS[@]}"; then
    log_error "unsupported environment '${env}' (expected one of: ${VALID_ENVS[*]})"
    return "${EX_USAGE}"
  fi
  return 0
}

# validate_service_name <name> - enforces kebab-case
validate_service_name() {
  local name="${1:-}"
  if [[ -z "${name}" ]]; then
    log_error "--name is required"
    return "${EX_USAGE}"
  fi
  if [[ ! "${name}" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    log_error "invalid name '${name}': expected kebab-case (e.g. fargate-cluster)"
    return "${EX_USAGE}"
  fi
  return 0
}

# --- Cloud metadata ----------------------------------------------------------

# csp_cli <cloud> - prints the provider's CLI binary name
csp_cli() {
  case "${1}" in
    aws) printf 'aws\n' ;;
    gcp) printf 'gcloud\n' ;;
    azure) printf 'az\n' ;;
    oracle) printf 'oci\n' ;;
    *) return 1 ;;
  esac
}

# csp_cli_hint <cloud> - prints an install/setup hint for the provider CLI
csp_cli_hint() {
  case "${1}" in
    aws) printf 'https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html\n' ;;
    gcp) printf 'https://cloud.google.com/sdk/docs/install\n' ;;
    azure) printf 'https://learn.microsoft.com/cli/azure/install-azure-cli\n' ;;
    oracle) printf 'https://docs.oracle.com/iaas/Content/API/SDKDocs/cliinstall.htm\n' ;;
    *) return 1 ;;
  esac
}

# tf_provider_meta <cloud> - prints "local-name|registry-source|min-version"
tf_provider_meta() {
  case "${1}" in
    aws) printf 'aws|hashicorp/aws|5.0\n' ;;
    gcp) printf 'google|hashicorp/google|5.0\n' ;;
    azure) printf 'azurerm|hashicorp/azurerm|3.0\n' ;;
    oracle) printf 'oci|oracle/oci|5.0\n' ;;
    *) return 1 ;;
  esac
}

# tf_backend_hint <cloud> - prints the expected remote state backend
tf_backend_hint() {
  case "${1}" in
    aws) printf 'S3 + DynamoDB lock table\n' ;;
    gcp) printf 'GCS bucket\n' ;;
    azure) printf 'Azure Blob Storage container\n' ;;
    oracle) printf 'OCI Object Storage bucket\n' ;;
    *) return 1 ;;
  esac
}

# --- Context (.cloud-context) ------------------------------------------------

# context_save <KEY=VALUE...> - overwrite the context file
context_save() {
  local kv
  local stamp
  stamp="$(utc_now)"
  umask 077
  {
    printf '# cloud-lab active cloud context\n'
    printf '# Written by scripts/cloud.switch.sh at %s\n' "${stamp}"
    printf '# Regenerate with: ./scripts/cloud.switch.sh --cloud <provider>\n'
    for kv in "$@"; do
      printf '%s\n' "${kv}"
    done
  } > "${CONTEXT_FILE}"
}

# context_load - export every KEY=VALUE pair from the context file
context_load() {
  if [[ ! -f "${CONTEXT_FILE}" ]]; then
    return 1
  fi
  local line key value
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" =~ ^[[:space:]]*(#.*)?$ ]]; then
      continue
    fi
    if [[ ! "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      log_warn "ignoring malformed line in ${CONTEXT_FILE}: ${line}"
      continue
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    export "${key}=${value}"
  done < "${CONTEXT_FILE}"
  return 0
}

# resolve_cloud [explicit-cloud] - explicit flag wins, else the saved context
resolve_cloud() {
  local cloud="${1:-}"
  if [[ -n "${cloud}" ]]; then
    printf '%s\n' "${cloud}"
    return 0
  fi
  context_load > /dev/null 2>&1 || true
  if [[ -n "${CLOUD_PROVIDER:-}" ]]; then
    printf '%s\n' "${CLOUD_PROVIDER}"
    return 0
  fi
  return 1
}

# --- Service and Terraform directory resolution ------------------------------

# service_dir <cloud> <service-path>
service_dir() { printf '%s/%s/%s\n' "${REPO_ROOT}" "$1" "$2"; }

# find_tf_dirs <root> - every directory below root that holds *.tf files
find_tf_dirs() {
  local root="$1"
  if [[ ! -d "${root}" ]]; then
    return 1
  fi
  find "${root}" -type f -name '*.tf' \
    -not -path '*/.terraform/*' \
    -printf '%h\n' 2> /dev/null | sort -u
}

# resolve_tf_dir <dir> - pick the single Terraform root to operate on.
# Order: the directory itself, then its infrastructure/ subdir, then the only
# *.tf-bearing descendant. Ambiguous trees return 1 so the caller can list
# candidates rather than guessing which stack to touch.
resolve_tf_dir() {
  local dir="$1"
  if compgen -G "${dir}/*.tf" > /dev/null 2>&1; then
    printf '%s\n' "${dir}"
    return 0
  fi
  if compgen -G "${dir}/infrastructure/*.tf" > /dev/null 2>&1; then
    printf '%s\n' "${dir}/infrastructure"
    return 0
  fi
  local -a candidates=()
  local d
  while IFS= read -r d; do
    candidates+=("${d}")
  done < <(find_tf_dirs "${dir}" || true)
  if [[ "${#candidates[@]}" -eq 1 ]]; then
    printf '%s\n' "${candidates[0]}"
    return 0
  fi
  return 1
}

# report_tf_candidates <cloud> <service> <dir> - explain an ambiguous resolve
report_tf_candidates() {
  local cloud="$1"
  local service="$2"
  local dir="$3"
  local d rel
  local -a candidates=()
  while IFS= read -r d; do
    candidates+=("${d}")
  done < <(find_tf_dirs "${dir}" || true)

  if [[ "${#candidates[@]}" -eq 0 ]]; then
    log_error "no Terraform files found under ${dir#"${REPO_ROOT}"/}"
    return 0
  fi
  log_error "'${service}' contains ${#candidates[@]} Terraform roots; pass a deeper --service path:"
  for d in "${candidates[@]}"; do
    rel="${d#"${REPO_ROOT}/${cloud}/"}"
    log_error "  --cloud ${cloud} --service ${rel}"
  done
  return 0
}

# require_service_dir <cloud> <service> - validate and print the service dir
require_service_dir() {
  local cloud="$1"
  local service="${2:-}"
  if [[ -z "${service}" ]]; then
    log_error "--service is required (e.g. compute/ecs)"
    return "${EX_USAGE}"
  fi
  local dir
  dir="$(service_dir "${cloud}" "${service}")"
  if [[ ! -d "${dir}" ]]; then
    log_error "service path does not exist: ${cloud}/${service}"
    log_error "  create it with: ./scripts/cloud.init.sh --cloud ${cloud} --category <category> --name <name>"
    return "${EX_USAGE}"
  fi
  printf '%s\n' "${dir}"
  return 0
}

# --- Shared option handling --------------------------------------------------

print_version() {
  printf '%s %s\n' "$(basename "${0}")" "${CLOUD_LAB_VERSION}"
}

# unknown_option <option> - consistent message for bad flags
unknown_option() {
  log_error "unknown option: $1"
  log_error "  run '$(basename "${0}") --help' for usage"
  return "${EX_USAGE}"
}
