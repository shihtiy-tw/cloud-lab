#!/usr/bin/env bash
#
# cloud.docs.sh - Generate Terraform documentation.
#
# Usage:
#   ./scripts/cloud.docs.sh --cloud aws --service compute/ecs
#   ./scripts/cloud.docs.sh --cloud aws --all
#   ./scripts/cloud.docs.sh --help
#
# See .opencode/command/cloud.docs.md
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

readonly VALID_FORMATS=(markdown json asciidoc)
readonly TFDOCS_CONFIG="${REPO_ROOT}/.terraform-docs.yml"
readonly MARKER_BEGIN='<!-- BEGIN_TF_DOCS -->'
readonly MARKER_END='<!-- END_TF_DOCS -->'

CLOUD=""
SERVICE=""
ALL=false
FORMAT=""
UPDATE_README=false
OUTPUT=""

show_help() {
  cat << EOF
Usage: $(basename "$0") --cloud <provider> --service <path> [OPTIONS]
       $(basename "$0") --cloud <provider> --all [OPTIONS]

Generate input/output/resource documentation with terraform-docs.

Required:
  --cloud <provider>     Cloud provider: ${VALID_CLOUDS[*]}
                         (falls back to CLOUD_PROVIDER in .cloud-context)
  --service <path>       Service path, e.g. compute/ecs   (or use --all)

Options:
  --all                  Document every Terraform directory under the cloud dir
  --update-readme        Inject into each directory's README.md (default for --all)
  --format <format>      ${VALID_FORMATS[*]} (default: markdown)
  --output <file>         Write to this file instead of a README (single dir only)
  --help                 Show this help message
  --version              Show version

Behaviour:
  With neither --format nor --output, the repository .terraform-docs.yml drives
  the output. Passing either flag switches to explicit CLI flags instead, since
  terraform-docs cannot mix a config file with conflicting format flags.

  README.md files are backed up to README.md.bak before being rewritten, and the
  BEGIN_TF_DOCS/END_TF_DOCS markers are appended when a README lacks them.

  Without --update-readme or --output, a single directory's docs go to stdout so
  the output can be piped or reviewed.

Exit codes:
  0 success    1 error    2 invalid usage    3 missing dependency

Examples:
  $(basename "$0") --cloud aws --service compute/ecs/infrastructure/cluster
  $(basename "$0") --cloud aws --all
  $(basename "$0") --cloud aws --service shared/modules/vpc --update-readme
  $(basename "$0") --cloud aws --service shared/modules/vpc --format json --output vpc.json
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
      --format)
        FORMAT="${2:-}"
        shift 2
        ;;
      --update-readme)
        UPDATE_README=true
        shift
        ;;
      --output)
        OUTPUT="${2:-}"
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

# tfdocs_format <format> - map our format names onto terraform-docs subcommands
tfdocs_format() {
  case "${1}" in
    markdown) printf 'markdown table\n' ;;
    json) printf 'json\n' ;;
    asciidoc) printf 'asciidoc table\n' ;;
    *) return 1 ;;
  esac
}

# ensure_markers <readme> - inject mode needs the marker pair to exist
ensure_markers() {
  local readme="$1"
  if [[ -f "${readme}" ]] && grep -qF "${MARKER_BEGIN}" "${readme}"; then
    return 0
  fi
  if [[ ! -f "${readme}" ]]; then
    log_info "creating ${readme#"${REPO_ROOT}"/}"
    printf '# %s\n\n' "$(basename "$(dirname "${readme}")")" > "${readme}"
  fi
  log_info "appending terraform-docs markers to ${readme#"${REPO_ROOT}"/}"
  printf '\n## Terraform reference\n\n%s\n%s\n' "${MARKER_BEGIN}" "${MARKER_END}" >> "${readme}"
  return 0
}

# generate <tf-dir> - run terraform-docs for one directory
generate() {
  local dir="$1"
  local rel="${dir#"${REPO_ROOT}"/}"

  local fmt_words
  fmt_words="$(tfdocs_format "${FORMAT:-markdown}")"

  local -a cmd=(terraform-docs)
  # shellcheck disable=SC2206  # deliberate word split: "markdown table" is two args
  cmd+=(${fmt_words})

  local use_config=false
  if [[ -z "${FORMAT}" && -z "${OUTPUT}" && -f "${TFDOCS_CONFIG}" ]]; then
    use_config=true
  fi

  if [[ "${use_config}" == true ]]; then
    cmd+=(--config "${TFDOCS_CONFIG}")
    # The repo config sets header-from: doc.md, which most directories lack.
    if [[ ! -f "${dir}/doc.md" ]]; then
      cmd+=(--header-from main.tf)
    fi
  fi

  local readme="${dir}/README.md"
  if [[ -n "${OUTPUT}" ]]; then
    cmd+=(--output-file "${OUTPUT}")
  elif [[ "${UPDATE_README}" == true || "${ALL}" == true ]]; then
    ensure_markers "${readme}"
    cp "${readme}" "${readme}.bak"
    cmd+=(--output-file README.md --output-mode inject)
  fi

  cmd+=("${dir}")

  log_info "${rel}: ${cmd[*]}"
  local rc=0
  "${cmd[@]}" || rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    log_error "${rel}: terraform-docs failed (exit ${rc})"
    return 1
  fi
  log_success "${rel}"
  return 0
}

main() {
  parse_args "$@"

  local resolved
  resolved="$(resolve_cloud "${CLOUD}" || true)"
  CLOUD="${resolved}"
  validate_cloud "${CLOUD}" || exit $?

  if [[ -n "${FORMAT}" ]] && ! in_list "${FORMAT}" "${VALID_FORMATS[@]}"; then
    die "${EX_USAGE}" "invalid --format '${FORMAT}' (expected one of: ${VALID_FORMATS[*]})"
  fi
  if [[ "${ALL}" != true && -z "${SERVICE}" ]]; then
    die "${EX_USAGE}" "either --service <path> or --all is required"
  fi
  if [[ -n "${OUTPUT}" && "${ALL}" == true ]]; then
    die "${EX_USAGE}" "--output writes a single file and cannot be combined with --all"
  fi

  require_cmd terraform-docs "https://terraform-docs.io/user-guide/installation/" || exit $?

  local search_root label
  if [[ "${ALL}" == true ]]; then
    search_root="${REPO_ROOT}/${CLOUD}"
    label="all"
    if [[ ! -d "${search_root}" ]]; then
      die "${EX_ERROR}" "cloud directory not found: ${CLOUD}/"
    fi
  else
    search_root="$(require_service_dir "${CLOUD}" "${SERVICE}")" || exit $?
    label="${SERVICE}"
  fi

  local -a dirs=()
  local d
  while IFS= read -r d; do
    dirs+=("${d}")
  done < <(find_tf_dirs "${search_root}" || true)

  if [[ "${#dirs[@]}" -eq 0 ]]; then
    die "${EX_ERROR}" "no Terraform files found under ${CLOUD}/${label}"
  fi

  if [[ -n "${OUTPUT}" && "${#dirs[@]}" -gt 1 ]]; then
    log_error "--output given but '${label}' spans ${#dirs[@]} Terraform directories"
    report_tf_candidates "${CLOUD}" "${label}" "${search_root}"
    exit "${EX_USAGE}"
  fi

  log_section "Documenting ${CLOUD}/${label} (${#dirs[@]} director$([[ "${#dirs[@]}" -eq 1 ]] && printf 'y' || printf 'ies'))"

  local failures=0
  for d in "${dirs[@]}"; do
    generate "${d}" || failures=$((failures + 1))
  done

  log_section "Summary"
  log_info "documented: $((${#dirs[@]} - failures))/${#dirs[@]}"
  if [[ "${failures}" -gt 0 ]]; then
    die "${EX_ERROR}" "${failures} director$([[ "${failures}" -eq 1 ]] && printf 'y' || printf 'ies') failed"
  fi
  if [[ "${UPDATE_README}" == true || "${ALL}" == true ]]; then
    log_info "previous READMEs kept as README.md.bak (git-ignored)"
  fi
  log_success "documentation generated"
}

main "$@"
