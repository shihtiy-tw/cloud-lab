#!/usr/bin/env bash
#
# cloud.init.sh - Scaffold a new cloud service.
#
# Usage:
#   ./scripts/cloud.init.sh --cloud aws --category compute --name fargate-cluster
#   ./scripts/cloud.init.sh --help
#
# See .opencode/command/cloud.init.md
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

readonly TERRATEST_VERSION="v0.46.7"
readonly TESTIFY_VERSION="v1.8.4"
readonly GO_VERSION="1.21"

CLOUD=""
CATEGORY=""
NAME=""
TEMPLATE=""
WITH_SCENARIOS=false
WITH_TESTS=true
FORCE=false

show_help() {
  cat <<EOF
Usage: $(basename "$0") --cloud <provider> --category <category> --name <name> [OPTIONS]

Scaffold a new cloud service with a standard directory layout, Terraform
skeleton, test module, and README.

Required:
  --cloud <provider>     Cloud provider: ${VALID_CLOUDS[*]}
                         (falls back to CLOUD_PROVIDER in .cloud-context)
  --category <category>  One of: ${VALID_CATEGORIES[*]}
  --name <name>          Service name in kebab-case, e.g. fargate-cluster

Options:
  --template <name>      Copy from shared/templates/<name> instead of generating
  --with-scenarios       Also create scenarios/basic/
  --with-tests           Create the test module (default)
  --no-tests             Skip the test module
  --force                Overwrite an existing service directory
  --help                 Show this help message
  --version              Show version

Generated layout:
  {cloud}/{category}/{name}/
  ├── infrastructure/{main,variables,outputs,versions}.tf
  │   └── terraform.tfvars.example
  ├── scenarios/basic/{main.tf,README.md}     (with --with-scenarios)
  ├── tests/{go.mod,unit/,integration/}       (unless --no-tests)
  ├── utils/.gitkeep
  └── README.md

Exit codes:
  0 success    1 error    2 invalid usage

Examples:
  $(basename "$0") --cloud aws --category compute --name fargate-cluster
  $(basename "$0") --cloud gcp --category storage --name gcs-bucket
  $(basename "$0") --cloud aws --category networking --name transit-gateway --with-scenarios
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cloud)
        CLOUD="${2:-}"
        shift 2
        ;;
      --category)
        CATEGORY="${2:-}"
        shift 2
        ;;
      --name)
        NAME="${2:-}"
        shift 2
        ;;
      --template)
        TEMPLATE="${2:-}"
        shift 2
        ;;
      --with-scenarios)
        WITH_SCENARIOS=true
        shift
        ;;
      --with-tests)
        WITH_TESTS=true
        shift
        ;;
      --no-tests)
        WITH_TESTS=false
        shift
        ;;
      --force)
        FORCE=true
        shift
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

# go_ident <kebab-name> - kebab-case to a valid Go identifier fragment
go_ident() {
  local name="$1"
  local out=""
  local part
  local IFS='-'
  for part in ${name}; do
    out+="${part^}"
  done
  printf '%s\n' "${out}"
}

# region_var <cloud> - the conventional region/location variable name
region_var() {
  case "${1}" in
    azure) printf 'location\n' ;;
    *) printf 'region\n' ;;
  esac
}

# region_default <cloud>
region_default() {
  case "${1}" in
    aws) printf 'us-east-1\n' ;;
    gcp) printf 'us-central1\n' ;;
    azure) printf 'eastus\n' ;;
    oracle) printf 'us-ashburn-1\n' ;;
    *) printf '\n' ;;
  esac
}

write_versions_tf() {
  local dir="$1"
  local provider="$2"
  local source="$3"
  local version="$4"
  cat >"${dir}/versions.tf" <<EOF
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # https://registry.terraform.io/providers/${source}/latest
    ${provider} = {
      source  = "${source}"
      version = ">= ${version}"
    }
  }
}
EOF
}

write_variables_tf() {
  local dir="$1"
  local rvar="$2"
  local rdefault="$3"

  cat >"${dir}/variables.tf" <<EOF
variable "project_name" {
  description = "Project or application name; used to name and tag resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "test", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, test, prod."
  }
}

variable "${rvar}" {
  description = "Cloud ${rvar} to deploy into."
  type        = string
  default     = "${rdefault}"
}

variable "owner" {
  description = "Team or individual responsible for these resources."
  type        = string
  default     = ""
}

variable "cost_center" {
  description = "Cost allocation code."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags merged into the common tag set."
  type        = map(string)
  default     = {}
}
EOF

  case "${CLOUD}" in
    gcp)
      cat >>"${dir}/variables.tf" <<'EOF'

variable "project_id" {
  description = "GCP project id."
  type        = string
}
EOF
      ;;
    azure)
      cat >>"${dir}/variables.tf" <<'EOF'

variable "resource_group_name" {
  description = "Azure resource group to deploy into."
  type        = string
}
EOF
      ;;
    oracle)
      cat >>"${dir}/variables.tf" <<'EOF'

variable "compartment_ocid" {
  description = "OCI compartment OCID to deploy into."
  type        = string
}
EOF
      ;;
    aws) ;;
    *) ;;
  esac
}

write_main_tf() {
  local dir="$1"
  local generated_on="$2"

  cat >"${dir}/main.tf" <<EOF
# ${CLOUD} ${CATEGORY} - ${NAME}
# Generated by scripts/cloud.init.sh on ${generated_on}

locals {
  name = "\${var.project_name}-${NAME}-\${var.environment}"

  # Required tags per docs/standards/TAGGING_STANDARDS.md
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Component   = "${CATEGORY}"
      Owner       = var.owner
      CostCenter  = var.cost_center
    },
    var.tags
  )
}

# TODO: declare the ${NAME} resources here.
EOF
}

write_outputs_tf() {
  local dir="$1"
  cat >"${dir}/outputs.tf" <<'EOF'
output "name" {
  description = "Generated base name for resources in this stack."
  value       = local.name
}

output "common_tags" {
  description = "Tag set applied to resources in this stack."
  value       = local.common_tags
}

# TODO: expose resource ids, ARNs/self-links, and endpoints here.
EOF
}

write_tfvars_example() {
  local dir="$1"
  local rvar="$2"
  local rdefault="$3"

  # One printf per line with a fixed field width keeps the '=' aligned whatever
  # the region variable is called.
  {
    printf '# Copy to terraform.tfvars (git-ignored) and adjust.\n'
    printf '%-19s = "%s"\n' 'project_name' 'my-app'
    printf '%-19s = "%s"\n' 'environment' 'dev'
    printf '%-19s = "%s"\n' "${rvar}" "${rdefault}"
    printf '%-19s = "%s"\n' 'owner' 'platform-team'
    printf '%-19s = "%s"\n' 'cost_center' 'engineering'
    case "${CLOUD}" in
      gcp) printf '%-19s = "%s"\n' 'project_id' 'my-project-123' ;;
      azure) printf '%-19s = "%s"\n' 'resource_group_name' 'my-rg' ;;
      oracle) printf '%-19s = "%s"\n' 'compartment_ocid' 'ocid1.compartment.oc1..example' ;;
      aws) ;;
      *) ;;
    esac
  } >"${dir}/terraform.tfvars.example"
}

write_scenario() {
  local scenario_dir="$1"
  local provider="$2"
  local source="$3"
  local version="$4"

  mkdir -p "${scenario_dir}"
  cat >"${scenario_dir}/main.tf" <<EOF
# Basic ${NAME} scenario
#
# Consumes the stack in ../../infrastructure with minimal inputs.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    ${provider} = {
      source  = "${source}"
      version = ">= ${version}"
    }
  }
}

module "${NAME//-/_}" {
  source = "../../infrastructure"

  project_name = "example"
  environment  = "dev"
}
EOF

  cat >"${scenario_dir}/README.md" <<EOF
# ${NAME} - basic scenario

Minimal working example of the \`${CLOUD}/${CATEGORY}/${NAME}\` stack.

## Usage

\`\`\`bash
make plan CLOUD=${CLOUD} SERVICE=${CATEGORY}/${NAME}/scenarios/basic ENV=dev
\`\`\`

## What this creates

TODO: describe the resources and their cost profile.
EOF
}

write_tests() {
  local tests_dir="$1"
  local ident="$2"

  mkdir -p "${tests_dir}/unit" "${tests_dir}/integration"

  # Each service test tree is its own Go module so it builds standalone.
  cat >"${tests_dir}/go.mod" <<EOF
module github.com/org/cloud-lab/${CLOUD}/${CATEGORY}/${NAME}/tests

go ${GO_VERSION}

require (
	github.com/gruntwork-io/terratest ${TERRATEST_VERSION}
	github.com/stretchr/testify ${TESTIFY_VERSION}
)
EOF

  cat >"${tests_dir}/unit/${NAME//-/_}_test.go" <<EOF
// Package test contains Terratest checks for ${CLOUD}/${CATEGORY}/${NAME}.
package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

// Test${ident}Validate initialises and validates the stack without creating
// anything, so it is safe to run without cloud credentials.
func Test${ident}Validate(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../infrastructure",
		Vars: map[string]interface{}{
			"project_name": "terratest",
			"environment":  "test",
		},
	})

	terraform.Init(t, terraformOptions)
	terraform.Validate(t, terraformOptions)
}
EOF

  cat >"${tests_dir}/integration/${NAME//-/_}_integration_test.go" <<EOF
// Package test contains integration tests for ${CLOUD}/${CATEGORY}/${NAME}.
//
// These create real cloud resources and cost money. Run them against a
// sandbox account only.
package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

// Test${ident}Apply provisions the stack, asserts on its outputs, and destroys
// it again.
func Test${ident}Apply(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../infrastructure",
		Vars: map[string]interface{}{
			"project_name": "terratest",
			"environment":  "test",
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	// TODO: assert on outputs, e.g.
	// name := terraform.Output(t, terraformOptions, "name")
	// assert.NotEmpty(t, name)
}
EOF
}

write_readme() {
  local dir="$1"
  local generated_on="$2"
  local title="${NAME//-/ }"

  cat >"${dir}/README.md" <<EOF
# ${CLOUD^^} ${CATEGORY^} - ${title^}

> Scaffolded by \`scripts/cloud.init.sh\` on ${generated_on}. Replace the TODOs.

## Overview

TODO: what this service provisions and when to use it.

## Layout

| Path                | Purpose                                  |
| ------------------- | ---------------------------------------- |
| \`infrastructure/\` | Terraform for the service itself         |
| \`scenarios/\`      | Runnable end-to-end usage examples       |
| \`tests/\`          | Terratest unit and integration tests     |
| \`utils/\`          | Helper scripts for this service          |

## Usage

\`\`\`bash
# Plan
make plan CLOUD=${CLOUD} SERVICE=${CATEGORY}/${NAME} ENV=dev

# Apply
make provision CLOUD=${CLOUD} SERVICE=${CATEGORY}/${NAME} ENV=dev

# Test
make test CLOUD=${CLOUD} SERVICE=${CATEGORY}/${NAME}

# Security scan
make security CLOUD=${CLOUD} SERVICE=${CATEGORY}/${NAME}

# Regenerate the Terraform docs block below
make docs CLOUD=${CLOUD} SERVICE=${CATEGORY}/${NAME}
\`\`\`

## Inputs and outputs

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->

## Cost

TODO: note the cost drivers and roughly what an idle stack costs.
EOF
}

# validate_template - check --template resolves before any directory is created
validate_template() {
  local template_dir="${REPO_ROOT}/shared/templates/${TEMPLATE}"
  if [[ -d "${template_dir}" ]]; then
    return 0
  fi
  log_error "template not found: shared/templates/${TEMPLATE}"
  if [[ -d "${REPO_ROOT}/shared/templates" ]]; then
    local available
    available="$(find "${REPO_ROOT}/shared/templates" -mindepth 1 -maxdepth 1 -type d -printf '%f ' 2>/dev/null || true)"
    if [[ -n "${available}" ]]; then
      log_error "  available: ${available}"
    else
      log_error "  shared/templates/ is empty"
    fi
  else
    log_error "  shared/templates/ does not exist; omit --template to use the built-in scaffold"
  fi
  return "${EX_USAGE}"
}

copy_template() {
  local template_dir="${REPO_ROOT}/shared/templates/${TEMPLATE}"
  if [[ ! -d "${template_dir}" ]]; then
    log_error "template not found: shared/templates/${TEMPLATE}"
    if [[ -d "${REPO_ROOT}/shared/templates" ]]; then
      local available
      available="$(find "${REPO_ROOT}/shared/templates" -mindepth 1 -maxdepth 1 -type d -printf '%f ' 2>/dev/null || true)"
      if [[ -n "${available}" ]]; then
        log_error "  available: ${available}"
      else
        log_error "  shared/templates/ is empty"
      fi
    else
      log_error "  shared/templates/ does not exist; omit --template to use the built-in scaffold"
    fi
    return "${EX_USAGE}"
  fi
  log_info "copying template ${TEMPLATE}"
  cp -r "${template_dir}/." "$1/"
  return 0
}

main() {
  parse_args "$@"

  local resolved
  resolved="$(resolve_cloud "${CLOUD}" || true)"
  CLOUD="${resolved}"
  validate_cloud "${CLOUD}" || exit $?
  validate_category "${CATEGORY}" || exit $?
  validate_service_name "${NAME}" || exit $?

  local cloud_dir="${REPO_ROOT}/${CLOUD}"
  if [[ ! -d "${cloud_dir}" ]]; then
    die "${EX_ERROR}" "cloud directory not found: ${CLOUD}/"
  fi

  local target="${cloud_dir}/${CATEGORY}/${NAME}"
  if [[ -d "${target}" ]]; then
    if [[ "${FORCE}" != true ]]; then
      log_error "service already exists: ${CLOUD}/${CATEGORY}/${NAME}"
      log_error "  pass --force to overwrite files in place"
      exit "${EX_USAGE}"
    fi
    log_warn "overwriting existing service ${CLOUD}/${CATEGORY}/${NAME} (--force)"
  fi

  # Fail before creating anything, so a bad --template leaves no empty dirs.
  if [[ -n "${TEMPLATE}" ]]; then
    validate_template || exit $?
  fi

  local generated_on
  generated_on="$(date -u '+%Y-%m-%d')"

  log_section "Scaffolding ${CLOUD}/${CATEGORY}/${NAME}"

  mkdir -p "${target}/infrastructure" "${target}/utils"
  touch "${target}/utils/.gitkeep"

  if [[ -n "${TEMPLATE}" ]]; then
    copy_template "${target}" || exit $?
  else
    local meta provider source version
    meta="$(tf_provider_meta "${CLOUD}")"
    IFS='|' read -r provider source version <<<"${meta}"

    local rvar rdefault
    rvar="$(region_var "${CLOUD}")"
    rdefault="$(region_default "${CLOUD}")"

    write_versions_tf "${target}/infrastructure" "${provider}" "${source}" "${version}"
    write_variables_tf "${target}/infrastructure" "${rvar}" "${rdefault}"
    write_main_tf "${target}/infrastructure" "${generated_on}"
    write_outputs_tf "${target}/infrastructure"
    write_tfvars_example "${target}/infrastructure" "${rvar}" "${rdefault}"
    log_success "infrastructure/ (main, variables, outputs, versions, tfvars.example)"

    if [[ "${WITH_SCENARIOS}" == true ]]; then
      write_scenario "${target}/scenarios/basic" "${provider}" "${source}" "${version}"
      log_success "scenarios/basic/"
    fi
  fi

  if [[ "${WITH_TESTS}" == true ]]; then
    local ident
    ident="$(go_ident "${NAME}")"
    write_tests "${target}/tests" "${ident}"
    log_success "tests/ (go.mod, unit, integration)"
  fi

  write_readme "${target}" "${generated_on}"
  log_success "README.md"

  if have_cmd terraform; then
    terraform fmt -recursive "${target}" >/dev/null 2>&1 ||
      log_warn "terraform fmt reported an issue in the generated files"
  fi

  log_section "Next steps"
  log_info "1. fill in the TODOs in ${CLOUD}/${CATEGORY}/${NAME}/infrastructure/main.tf"
  log_info "2. make plan CLOUD=${CLOUD} SERVICE=${CATEGORY}/${NAME} ENV=dev"
  log_info "3. make docs CLOUD=${CLOUD} SERVICE=${CATEGORY}/${NAME}"
  log_success "scaffolded ${CLOUD}/${CATEGORY}/${NAME}"
}

main "$@"
