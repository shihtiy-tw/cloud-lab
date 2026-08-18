#!/usr/bin/env bash
#
# cloud.test.sh - Run Terratest infrastructure tests.
#
# Usage:
#   ./scripts/cloud.test.sh --cloud aws --service compute/ecs
#   ./scripts/cloud.test.sh --cloud aws --all
#   ./scripts/cloud.test.sh --help
#
# See .opencode/command/cloud.test.md
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

readonly VALID_SUITES=(unit integration all)

CLOUD=""
SERVICE=""
ALL=false
SUITE="all"
VERBOSE=false
TIMEOUT="10m"
PARALLEL=""

show_help() {
  cat << EOF
Usage: $(basename "$0") --cloud <provider> --service <path> [OPTIONS]
       $(basename "$0") --cloud <provider> --all [OPTIONS]

Run Go/Terratest infrastructure tests. Every Go module (a directory with a
go.mod) below the search root is tested in turn.

Required:
  --cloud <provider>     Cloud provider: ${VALID_CLOUDS[*]}
                         (falls back to CLOUD_PROVIDER in .cloud-context)
  --service <path>       Service path, e.g. compute/ecs   (or use --all)

Options:
  --all                  Test every module under the cloud directory
  --suite <suite>        ${VALID_SUITES[*]} (default: all)
  --verbose              Pass -v to go test
  --timeout <duration>   go test timeout (default: ${TIMEOUT}; use 30m for apply tests)
  --parallel <n>         Pass -parallel <n> to go test
  --help                 Show this help message
  --version              Show version

Notes:
  Integration suites create real cloud resources. Point .cloud-context at a
  sandbox account before running --suite integration or --suite all.

  With --service and no test module present, this exits 1: you asked for a
  specific service's tests and there are none. With --all it warns and exits 0.

Exit codes:
  0 success    1 test failure or no tests for an explicit --service
  2 invalid usage    3 missing dependency

Examples:
  $(basename "$0") --cloud aws --service compute/ecs
  $(basename "$0") --cloud aws --all --suite unit
  $(basename "$0") --cloud aws --service compute/ecs --suite integration --timeout 30m
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
      --suite)
        SUITE="${2:-}"
        shift 2
        ;;
      --verbose | -v)
        VERBOSE=true
        shift
        ;;
      --timeout)
        TIMEOUT="${2:-}"
        shift 2
        ;;
      --parallel)
        PARALLEL="${2:-}"
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

# find_go_modules <root> - directories below root that contain a go.mod
find_go_modules() {
  local root="$1"
  if [[ ! -d "${root}" ]]; then
    return 1
  fi
  find "${root}" -type f -name 'go.mod' \
    -not -path '*/vendor/*' \
    -printf '%h\n' 2> /dev/null | sort -u
}

# suite_pattern <module-dir> - the go test package pattern for the chosen suite
suite_pattern() {
  local dir="$1"
  case "${SUITE}" in
    unit)
      if [[ -d "${dir}/unit" ]]; then
        printf './unit/...\n'
      else
        printf './...\n'
      fi
      ;;
    integration)
      if [[ -d "${dir}/integration" ]]; then
        printf './integration/...\n'
      else
        printf './...\n'
      fi
      ;;
    *)
      printf './...\n'
      ;;
  esac
}

# module_has_tests <module-dir> <pattern>
module_has_tests() {
  local dir="$1"
  local scope="${dir}"
  case "${SUITE}" in
    unit) [[ -d "${dir}/unit" ]] && scope="${dir}/unit" ;;
    integration) [[ -d "${dir}/integration" ]] && scope="${dir}/integration" ;;
    *) ;;
  esac
  local found
  found="$(find "${scope}" -type f -name '*_test.go' -not -path '*/vendor/*' -print -quit 2> /dev/null || true)"
  [[ -n "${found}" ]]
}

# run_module <module-dir> - returns the go test exit code
run_module() {
  local dir="$1"
  local rel="${dir#"${REPO_ROOT}"/}"
  local pattern
  pattern="$(suite_pattern "${dir}")"

  if ! module_has_tests "${dir}"; then
    log_warn "${rel}: no ${SUITE} *_test.go files; skipping"
    return 0
  fi

  local -a cmd=(go test -timeout "${TIMEOUT}")
  if [[ "${VERBOSE}" == true ]]; then
    cmd+=(-v)
  fi
  if [[ -n "${PARALLEL}" ]]; then
    cmd+=(-parallel "${PARALLEL}")
  fi
  cmd+=("${pattern}")

  log_section "${rel} (${SUITE})"
  log_info "${cmd[*]}"

  local rc=0
  (cd "${dir}" && "${cmd[@]}") || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    log_success "${rel}: passed"
  else
    log_error "${rel}: failed (exit ${rc})"
  fi
  return "${rc}"
}

main() {
  parse_args "$@"

  local resolved
  resolved="$(resolve_cloud "${CLOUD}" || true)"
  CLOUD="${resolved}"
  validate_cloud "${CLOUD}" || exit $?

  if ! in_list "${SUITE}" "${VALID_SUITES[@]}"; then
    die "${EX_USAGE}" "invalid --suite '${SUITE}' (expected one of: ${VALID_SUITES[*]})"
  fi

  if [[ "${ALL}" != true && -z "${SERVICE}" ]]; then
    die "${EX_USAGE}" "either --service <path> or --all is required"
  fi

  require_cmd go "https://go.dev/dl/ (Go ${GO_MIN_VERSION:-1.21}+)" || exit $?

  local search_root
  if [[ "${ALL}" == true ]]; then
    search_root="${REPO_ROOT}/${CLOUD}"
    if [[ ! -d "${search_root}" ]]; then
      die "${EX_ERROR}" "cloud directory not found: ${CLOUD}/"
    fi
  else
    search_root="$(require_service_dir "${CLOUD}" "${SERVICE}")" || exit $?
  fi

  if context_load; then
    log_info "loaded provider context from ${CONTEXT_FILE#"${REPO_ROOT}"/}"
  else
    log_warn "no .cloud-context found; tests will use the ambient environment"
  fi

  if [[ "${SUITE}" == "integration" || "${SUITE}" == "all" ]]; then
    log_warn "integration tests create billable cloud resources; use a sandbox account"
  fi

  local -a modules=()
  local m
  while IFS= read -r m; do
    modules+=("${m}")
  done < <(find_go_modules "${search_root}" || true)

  if [[ "${#modules[@]}" -eq 0 ]]; then
    if [[ "${ALL}" == true ]]; then
      log_warn "no Go test modules found under ${CLOUD}/"
      log_warn "  scaffold one with: ./scripts/cloud.init.sh --cloud ${CLOUD} --category <c> --name <n>"
      exit "${EX_OK}"
    fi
    log_error "no Go test module (go.mod) found under ${CLOUD}/${SERVICE}"
    if [[ -d "${REPO_ROOT}/${CLOUD}/tests" ]]; then
      log_error "  cloud-level tests exist; try: $(basename "$0") --cloud ${CLOUD} --all"
    fi
    exit "${EX_ERROR}"
  fi

  log_info "found ${#modules[@]} Go module(s)"

  local failures=0
  local passed=0
  for m in "${modules[@]}"; do
    local rc=0
    run_module "${m}" || rc=$?
    if [[ "${rc}" -eq 0 ]]; then
      passed=$((passed + 1))
    else
      failures=$((failures + 1))
    fi
  done

  log_section "Summary"
  log_info "modules passed: ${passed}"
  if [[ "${failures}" -gt 0 ]]; then
    log_error "modules failed: ${failures}"
    exit "${EX_ERROR}"
  fi
  log_success "all ${passed} module(s) passed"
}

main "$@"
